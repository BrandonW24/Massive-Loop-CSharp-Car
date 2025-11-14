using ML.SDK;
using TMPro;
using UnityEngine;
using UnityEngine.UI;

public class CarDriver_CSharp : MonoBehaviour
{
    // Constants
    private const float NEAR_ZERO = 0.01f;
    private const float ENGINE_IDLE_RPM = 800f;
    private const float ENGINE_MAX_RPM = 8000f;

    // Gearbox values (now local variables instead of a class)
    private float[] gearRatios = { 3f, 3f, 2f, 1.5f, 1f, 0.5f };
    private float gearFactor = 3.75f;
    private float diffRatio = 0.65f;
    private int currentGear = 2;
    private const int MIN_GEAR_INDEX = 2;
    private const int MAX_GEAR_INDEX = 6;
    private const int REVERSE_GEAR_INDEX = 1;

    // Engine state
    public enum EngineState
    {
        Off,
        Startup,
        Idle,
        Acceleration
    }

    public class CarEngine
    {
        public float rpm = 0;
        public EngineState state = EngineState.Off;
        public float startTime = 0;

        public void CalculateCurrentEngineState(float throttle, float speed, WheelCollider wheelBL, CarDriver_CSharp car)
        {
            if (state == EngineState.Off || state == EngineState.Startup)
            {
                rpm = 0;
                if (state == EngineState.Startup && Time.time - startTime > 3)
                {
                    state = EngineState.Idle;
                }
                return;
            }

            float wheelRPM = (speed * 60) / (2 * Mathf.PI * wheelBL.radius);
            wheelRPM = Mathf.Abs(wheelRPM) * ((car.gearFactor * car.gearRatios[car.currentGear - 1]) + car.diffRatio);

            if (wheelRPM > ENGINE_MAX_RPM * 0.7f)
            {
                if (car.currentGear < MAX_GEAR_INDEX)
                {
                    car.currentGear++;
                }
            }
            if (wheelRPM < ENGINE_MAX_RPM * 0.5f)
            {
                if (car.currentGear > MIN_GEAR_INDEX)
                {
                    car.currentGear--;
                }
            }

            float targetRPM = wheelRPM + Mathf.Lerp(0, ENGINE_MAX_RPM / 16, Mathf.Abs(throttle));
            rpm = Mathf.MoveTowards(rpm, targetRPM, 100);

            if (throttle <= 0.05f)
            {
                state = EngineState.Idle;
            }
            else
            {
                state = EngineState.Acceleration;
            }

            rpm = Mathf.Clamp(rpm, ENGINE_IDLE_RPM, ENGINE_MAX_RPM);
        }

        public float GetEngineTorque(float engineRPM)
        {
            float rpm = Mathf.Clamp(engineRPM / ENGINE_MAX_RPM, 0, 1);
            return Mathf.Clamp(Mathf.Sin(Mathf.Sqrt(rpm) * Mathf.PI) * 0.58f + Mathf.Sin(rpm * rpm * Mathf.PI) * 0.58f + 0.095f, 0, 1);
        }
    }

    public CarEngine carEngine = new CarEngine();

    // Serialized fields
    public WheelCollider wheelFR;
    public WheelCollider wheelFL;
    public WheelCollider wheelBR;
    public WheelCollider wheelBL;

    public Rigidbody Car_RB;
    public GameObject steeringWheel;
    public GameObject speedDial;
    public GameObject engineRPMDial;
    public GameObject localControlIndicator;
    public Transform syncObject;
    public Transform centerOfMass;
    public MLStation station;

    public float THROTTLE_FACTOR = 0.1f;
    public float STEERING_FACTOR = 0.1f;
    public float MOTOR_MAX_TORQUE = 2000f;
    public float STEERING_ANGLE_MAX = 30f;
    public float MAX_BREAK_TORQUE = 1000f;
    public bool useAckerman = true;
    public float handBreakTorque = 1000f;
    public bool useCurvedSteeringInVR = true;

    public GameObject minimapMarker;

    public AudioSource engineStartupAudio;
    public AudioSource engineIdleAudio;
    public AudioSource engineAccelerationAudio;
    public AudioSource engineDriveAudio;

    public AudioSource windAudio;
    public AudioClip impact;

    public Text gearIndicator;
    public Text debugText;

    public GameObject directionIndicator;
    public TextMeshPro nextGateText; // Optional text display
    private int currentTargetGate = 1;

    // Internal variables
    private int direction = 1;
    private float throttle = 0;
    private float steering = 0;
    private float breaks = 0;
    private float speed = 0;
    private float speedSMA = 0;
    private int speedSMASamplesSize = 10;
    private float[] previousSpeeds = new float[10];
    private float wheelBase = 0;
    private float track = 0;
    private float turningRadius = 0;
    private bool underLocalPlayerControl = false;
    private Vector3 lastPost = Vector3.zero;
    public MLPlayer currentDriver;
    public SkinnedMeshRenderer Decal_1;
    public MeshRenderer Decal_2;
    public GameObject WindObject;

    public GameObject RacingManagerOBJ;
 //   public RacingGameManager RacingGameManagerReference;
    private void Start()
    {
        Debug.Log("Checking if car is alive...");
        wheelBase = Vector3.Distance(wheelBL.transform.position, wheelFR.transform.position);
        track = Vector3.Distance(wheelFL.transform.position, wheelFR.transform.position);
        float betaAngleRadian = (180 - (STEERING_ANGLE_MAX + 90)) * Mathf.Deg2Rad;
        turningRadius = (Mathf.Abs(Mathf.Tan(betaAngleRadian) * wheelBase)) + (track / 2);

        Car_RB.centerOfMass = centerOfMass.localPosition;

      //  RacingGameManagerReference = RacingManagerOBJ.GetComponent(typeof(RacingGameManager)) as RacingGameManager;


        for (int i = 0; i < speedSMASamplesSize; i++)
        {
            previousSpeeds[i] = 0;
        }

        lastPost = transform.position;

        station.OnPlayerSeated.AddListener(OnPlayerEnterStation);
        station.OnPlayerLeft.AddListener(OnPlayerLeftStation);

        if (station.IsOccupied)
        {
            carEngine.state = EngineState.Idle;
        }

        engineIdleAudio.Play();
        engineAccelerationAudio.Play();
        engineDriveAudio.Play();
        windAudio.Play();
    }

    private void Update()
    {
        if (station.IsOccupied)
        {
            var player = station.GetPlayer();
            if (player.IsLocal)
            {
                Car_RB.drag = 0;
                Car_RB.angularDrag = 0;

                underLocalPlayerControl = true;
                var input = station.GetStationInput();
                if (direction == 0)
                {
                    direction = 1;
                }

                if (MassiveLoopClient.IsInDesktopMode)
                {
                    HandleDesktopModeInput(input);
                }
                else
                {
                    HandleVRModeInput(input);
                }
            }
            else
            {
                underLocalPlayerControl = false;
            }
        }
        else
        {
            underLocalPlayerControl = false;
            Car_RB.velocity = Vector3.zero;
            Car_RB.angularVelocity = Vector3.zero;
            Car_RB.drag = 15;
            Car_RB.angularDrag = 30;
        }

        if (underLocalPlayerControl)
        {
            syncObject.localPosition = new Vector3(throttle, steering, direction);
        }
        else
        {
            var localPos = syncObject.localPosition;
            throttle = localPos.x;
            steering = localPos.y;
            direction = (int)localPos.z;
        }

        steeringWheel.transform.localRotation = Quaternion.Euler(-steering * STEERING_ANGLE_MAX * 4, -90, 0);
        speedDial.transform.localRotation = Quaternion.Euler(0, Mathf.LerpUnclamped(-42, 71, Mathf.Abs(speedSMA / 100) * 2.23694f), 0);
        engineRPMDial.transform.localRotation = Quaternion.Euler(0, Mathf.Lerp(-135, 135, Mathf.InverseLerp(0, ENGINE_MAX_RPM, carEngine.rpm)), 0);

        gearIndicator.text = direction < 0 ? "R" : $"D{currentGear - 1}";
//        UpdateDirectionIndicator();


    }

    /*

    private void UpdateDirectionIndicator()
    {
        if (station.IsOccupied && RacingGameManagerReference != null)
        {
            // Get player progress from GameManager
            string playerName = station.GetPlayer().NickName;
            int lastGate = RacingGameManagerReference.GetPlayerLastGate(playerName);
            currentTargetGate = (lastGate % RacingGameManagerReference.TotalGates) + 1;

            // Point toward next gate
            if (directionIndicator != null)
            {
                Transform targetGate = RacingGameManagerReference.GetGateTransform(currentTargetGate);
                if (targetGate != null)
                {
                    directionIndicator.transform.LookAt(targetGate);
                    // Keep the arrow horizontal (only rotate on Y axis)
                    directionIndicator.transform.rotation = Quaternion.Euler(
                        0,
                        directionIndicator.transform.eulerAngles.y,
                        0
                    );
                }
            }

            // Update text if available
            if (nextGateText != null)
            {
                nextGateText.text = $"Gate: {currentTargetGate}";
            }
        }
    }
    */

    private void FixedUpdate()
    {
        if (underLocalPlayerControl)
        {
            speed = (wheelFL.rpm * wheelFL.radius * Mathf.PI * 2) * 0.06f;
        }
        else
        {
            speed = Vector3.Distance(lastPost, transform.position) / Time.fixedDeltaTime;
            lastPost = transform.position;
        }

        previousSpeeds[Time.frameCount % speedSMASamplesSize] = speed;

        float samplesSum = 0;
        foreach (var value in previousSpeeds)
        {
            samplesSum += value;
        }

        speedSMA = samplesSum / speedSMASamplesSize;

        localControlIndicator.SetActive(underLocalPlayerControl);

        debugText.text = $"Engine RPM: {carEngine.rpm}\nCurrent Gear: {currentGear}\nThrottle: {throttle:F3}\nDirection: {direction}\nEngine State: {carEngine.state}";

        if (underLocalPlayerControl)
        {
            if (speedSMA > 1 && ((direction > 0 && speedSMA < 0) || (direction < 0 && speedSMA > 0)))
            {
                direction = -direction;
            }

            if (breaks < NEAR_ZERO)
            {
                wheelFL.brakeTorque = 0;
                wheelFR.brakeTorque = 0;
                wheelBL.brakeTorque = 0;
                wheelBR.brakeTorque = 0;

                if ((throttle > 0 && direction > 0) || (throttle < 0 && direction < 0))
                {
                    float rpmRelativeT = carEngine.GetEngineTorque(carEngine.rpm);
                    float wheelTorque = throttle * rpmRelativeT * MOTOR_MAX_TORQUE * (gearFactor * gearRatios[currentGear - 1]) / 2;
                    debugText.text += $"\nrpm: {rpmRelativeT:F4}";
                    wheelBL.motorTorque = wheelTorque;
                    wheelBR.motorTorque = wheelTorque;
                }
                else
                {
                    wheelBL.motorTorque = 0;
                    wheelBR.motorTorque = 0;
                }
            }
            else
            {
                float breaking = breaks * MAX_BREAK_TORQUE + speedSMA * 2;
                wheelFL.brakeTorque = breaking;
                wheelFR.brakeTorque = breaking;
                wheelBL.brakeTorque = breaking / 2;
                wheelBR.brakeTorque = breaking / 2;
            }
        }
        else
        {
            wheelBL.brakeTorque = 0;
            wheelBR.brakeTorque = 0;
            wheelFL.brakeTorque = 0;
            wheelFR.brakeTorque = 0;
        }

        if (useAckerman)
        {
            float ackAngleLeft = 0;
            float ackAngleRight = 0;

            float halfTrack = track / 2;
            if (steering > 0)
            {
                ackAngleLeft = Mathf.Rad2Deg * Mathf.Atan(wheelBase / (turningRadius + halfTrack)) * steering / 2;
                ackAngleRight = Mathf.Rad2Deg * Mathf.Atan(wheelBase / (turningRadius - halfTrack)) * steering / 2;
            }
            else if (steering < 0)
            {
                ackAngleLeft = Mathf.Rad2Deg * Mathf.Atan(wheelBase / (turningRadius - halfTrack)) * steering / 2;
                ackAngleRight = Mathf.Rad2Deg * Mathf.Atan(wheelBase / (turningRadius + halfTrack)) * steering / 2;
            }

            wheelFR.steerAngle = ackAngleRight;
            wheelFL.steerAngle = ackAngleLeft;
        }
        else
        {
            wheelFR.steerAngle = steering * STEERING_ANGLE_MAX;
            wheelFL.steerAngle = steering * STEERING_ANGLE_MAX;
        }

        if (underLocalPlayerControl)
        {
            carEngine.CalculateCurrentEngineState(throttle, 2 * Mathf.PI * wheelBL.radius * (wheelBL.rpm / 60), wheelBL, this);
        }
        else
        {
            carEngine.CalculateCurrentEngineState(throttle, speedSMA, wheelBL, this);
        }

        HandleEngineAudioEffects();
        HandleOtherAudioEffects();
    }

    private void OnCollisionEnter(Collision collision)
    {
        if (collision != null)
        {
            /*
            var contact = collision.GetContact(0);
            if (contact != null)
            {
                AudioSource.PlayClipAtPoint(impact, contact.point, collision.impulse.magnitude / 10);
            }*/
        }
    }

    private void OnPlayerEnterStation()
    {
        engineStartupAudio.Play();
        carEngine.state = EngineState.Startup;
        carEngine.startTime = Time.time;

        Car_RB.drag = 0;
        Car_RB.angularDrag = 0;

        currentDriver = station.GetPlayer();
        Debug.Log($"Current driver : {currentDriver}");

        // Load thumbnail with callback
        currentDriver.LoadPlayerThumbnail((texture) =>
        {
            if (texture != null)
            {
                Decal_1.material.mainTexture = texture;
                if(Decal_2 != null)
                {

                    Decal_2.material.mainTexture = texture;
                }
            }
            else
            {
                Debug.LogWarning("Failed to load player thumbnail");
            }
        });
    }

    private void OnPlayerLeftStation()
    {
        throttle = 0;
        wheelBL.brakeTorque = handBreakTorque;
        wheelBR.brakeTorque = handBreakTorque;
        wheelFL.brakeTorque = handBreakTorque;
        wheelFR.brakeTorque = handBreakTorque;

        breaks = 1;
        carEngine.state = EngineState.Off;

        Car_RB.velocity = Vector3.zero;
        Car_RB.angularVelocity = Vector3.zero;
        currentDriver = null;
    }

    private void HandleDesktopModeInput(UserStationInput input)
    {
        if (input.KeyboardMove.y > 0.5f)
        {
            throttle += THROTTLE_FACTOR;
            throttle = Mathf.Clamp(throttle, -1, 1);

            if (direction > 0)
            {
                if (throttle > 0)
                {
                    breaks = 0;
                }
            }
            else
            {
                if (throttle > 0)
                {
                    breaks += THROTTLE_FACTOR;
                }

                breaks = Mathf.Clamp(breaks, 0, 1);

                if (speedSMA < NEAR_ZERO)
                {
                    throttle = 0;
                    direction = -direction;
                }
            }
        }
        else if (input.KeyboardMove.y < -0.5f)
        {
            if (direction > 0)
            {
                throttle -= THROTTLE_FACTOR * 2;
                if (throttle < 0)
                {
                    breaks += THROTTLE_FACTOR;
                }

                throttle = Mathf.Clamp(throttle, -1, 1);
                breaks = Mathf.Clamp(breaks, 0, 1);

                if (speedSMA < 1)
                {
                    throttle = 0;
                    direction = -direction;
                }
            }
            else
            {
                throttle -= THROTTLE_FACTOR;
                if (throttle < 0)
                {
                    breaks = 0;
                }

                throttle = Mathf.Clamp(throttle, -1, -0.8f);
            }
        }
        else
        {
            throttle = Mathf.MoveTowards(throttle, 0, THROTTLE_FACTOR);
        }

        if (input.KeyboardMove.x > 0.5f)
        {
            steering += STEERING_FACTOR;
            steering = Mathf.Clamp(steering, -1, 1);
        }
        else if (input.KeyboardMove.x < -0.5f)
        {
            steering -= STEERING_FACTOR;
            steering = Mathf.Clamp(steering, -1, 1);
        }
        else
        {
            steering = Mathf.MoveTowards(steering, 0, STEERING_FACTOR / 5);
        }

        if (input.Jump)
        {
            wheelBL.brakeTorque = handBreakTorque;
            wheelBR.brakeTorque = handBreakTorque;
        }
        else
        {
            wheelBL.brakeTorque = 0;
            wheelBR.brakeTorque = 0;
        }
    }

    private void HandleVRModeInput(UserStationInput input)
    {
        throttle = input.LeftControl.y;

        float steeringTarget = 0;

        if (useCurvedSteeringInVR)
        {
            steeringTarget = Mathf.Tan(input.RightControl.x / 0.685f) * 0.113f;
        }
        else
        {
            steeringTarget = input.RightControl.x;
        }

        steering = Mathf.MoveTowards(steering, steeringTarget, 1.5f * Time.deltaTime);

        if (direction > 0)
        {
            if (throttle > NEAR_ZERO)
            {
                breaks = 0;
            }
            else
            {
                breaks = Mathf.Abs(throttle);
                throttle = 0;

                if (speedSMA < 1)
                {
                    direction = -direction;
                }
            }
        }
        else if (direction < 0)
        {
            if (throttle > NEAR_ZERO)
            {
                breaks = Mathf.Abs(throttle);
                throttle = 0;

                if (speedSMA > -1)
                {
                    direction = -direction;
                }
            }
            else
            {
                if (throttle < -0.8f)
                {
                    throttle = -0.8f;
                }

                breaks = 0;
            }
        }
    }

    private void HandleEngineAudioEffects()
    {
        if (carEngine.state == EngineState.Off)
        {
            engineAccelerationAudio.volume = 0;
            engineDriveAudio.volume = 0;
            engineIdleAudio.volume = 0;
        }
        else if (carEngine.state == EngineState.Startup)
        {
            engineAccelerationAudio.volume = 0;
            engineDriveAudio.volume = 0;
            engineIdleAudio.volume = 0;
        }
        else
        {
            float trueThrottle = 0;
            if (direction >= 0 && throttle >= 0)
            {
                trueThrottle = Mathf.Clamp(throttle, 0, 1);
            }
            else if (direction < 0 && throttle < 0)
            {
                trueThrottle = Mathf.Clamp(Mathf.Abs(throttle), 0, 1);
            }

            float rpmFactor = Mathf.InverseLerp(ENGINE_IDLE_RPM, ENGINE_MAX_RPM, carEngine.rpm);

            engineAccelerationAudio.volume = trueThrottle;
            engineAccelerationAudio.pitch = Mathf.Lerp(0.8f, 1.5f, rpmFactor);

            engineIdleAudio.pitch = Mathf.Lerp(1, 1.8f, rpmFactor + throttle);
            engineIdleAudio.volume = Mathf.Lerp(1, 0, rpmFactor);

            engineDriveAudio.pitch = Mathf.Lerp(0.5f, 1.5f, rpmFactor);
            engineDriveAudio.volume = Mathf.Lerp(0.2f, 1, rpmFactor);
        }
    }

    private void HandleOtherAudioEffects()
    {
        float speedFactor = Mathf.InverseLerp(0, 50, speedSMA);
        windAudio.volume = Mathf.Lerp(0, 1, speedFactor);
        windAudio.pitch = Mathf.Lerp(1, 1.3f, speedFactor);
    }
}