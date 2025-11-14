using UnityEngine;

public class WheelController : MonoBehaviour
{
    [Header("References")]
    [SerializeField] private WheelCollider wheelCollider;
    [SerializeField] private GameObject wheelObj;
    [SerializeField] private GameObject innerWheelObj;
    [SerializeField] private AudioSource screechNoise;
    [SerializeField] private GameObject particles;

    [Header("Settings")]
    private const string SLIPPING_EVENT_NAME = "s";

    private bool isOwned = false;
    private Vector3 lastPos = Vector3.zero;
    private bool isSlipping = false;
    private bool slippingEventCheck = false;

    private void Start()
    {
        lastPos = transform.position;

        wheelCollider.suspensionDistance = 0.2f; // Adjust based on your needs
        wheelCollider.forceAppPointDistance = 0.5f; // Center of mass offset

        // Note: You'll need to replace this with your own ownership check system
        // isOwned = gameObject.GetOwner() == Room.GetLocalPlayer();

        // Register event for handling slipping
        // Note: Replace with your own event system
        // LuaEvents.AddLocal(this, SLIPPING_EVENT_NAME, HandleSlippingEvent);
    }

    private void Update()
    {
        // Move wheel object position and rotation based on the wheelCollider
        wheelCollider.GetWorldPose(out Vector3 pos, out Quaternion rot);
        wheelObj.transform.position = pos;
        wheelObj.transform.rotation = rot * Quaternion.Euler(0, -90, 0);

        // Calculate speed
        float speed = (2 * Mathf.PI * wheelCollider.radius) * (wheelCollider.rpm / 60);

        if (!isOwned)
        {
            // The wheel collider has a hard time calculating the wheel roll rotation when 
            // the physics is not calculated in the local client, so instead, we do a roll 
            // calculation based on wheel positional speed, radius and direction and apply 
            // it to the inner wheel object.

            // Distance moved since last frame
            float movementDist = Vector3.Distance(transform.position, lastPos);

            // Speed 
            speed = movementDist / Time.deltaTime;

            // Find dot product to determine the rotation direction
            float dot = Vector3.Dot(transform.parent.right, lastPos - transform.position);
            float sign = 1;
            if (dot < 0)
            {
                sign = -1;
            }
            else if (dot == 0)
            {
                sign = 0;
            }

            // Rotational speed
            float wheelTurnsDeg = (360 * movementDist / (2 * wheelCollider.radius * Mathf.PI)) * sign;

            innerWheelObj.transform.Rotate(new Vector3(0, 0, wheelTurnsDeg), Space.Self);

            lastPos = wheelCollider.transform.position;
        }

        // Apply screech noise volume based on wheel speed
        screechNoise.volume = Mathf.Lerp(0, 1, Mathf.InverseLerp(0, 20, speed));

        // Play screechNoise if the wheel is slipping
        if (isSlipping)
        {
            if (!screechNoise.isPlaying)
            {
                screechNoise.Play();
                if (particles != null)
                {
                    particles.SetActive(true);
                }
            }
        }
        else
        {
            if (screechNoise.isPlaying)
            {
                screechNoise.Stop();
                if (particles != null)
                {
                    particles.SetActive(false);
                }
            }
        }
    }

    private void FixedUpdate()
    {
        if (isOwned)
        {
            // Determine if the wheel is slipping
            WheelHit wheelHit;
            bool isWheelHittingGround = wheelCollider.GetGroundHit(out wheelHit);

            if (isWheelHittingGround)
            {
                isSlipping = Mathf.Abs(wheelHit.forwardSlip) > 1 || Mathf.Abs(wheelHit.sidewaysSlip) > 0.2f;
            }
            else
            {
                isSlipping = false;
            }

            if (isSlipping)
            {
                if (!slippingEventCheck)
                {
                    // Note: Replace with your own networking event system
                    // LuaEvents.InvokeLocalNetwork(this, SLIPPING_EVENT_NAME, EventTarget.Others, null, true);
                    slippingEventCheck = true;
                }
            }
            else
            {
                if (slippingEventCheck)
                {
                    // Note: Replace with your own networking event system
                    // LuaEvents.InvokeLocalNetwork(this, SLIPPING_EVENT_NAME, EventTarget.Others, null, false);
                    slippingEventCheck = false;
                }
            }
        }
    }

    // Note: You'll need to implement these methods based on your ownership system
    private void OnBecomeOwner()
    {
        isOwned = true;
    }

    private void OnLostOwnership()
    {
        isOwned = false;
    }

    // Example event handler (replace with your actual implementation)
    private void HandleSlippingEvent(bool slip)
    {
        isSlipping = slip;
    }
}