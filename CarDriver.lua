Namespace("brandonw_gokarts.yashar_ml_speeder");
do -- script NewLuaBehavior 
	
	--- zero epsilon. 
	local NEAR_ZERO = 0.0001;

	--- @class GEAR_BOX
	--- the car's gearbox setup
	local GEAR_BOX = {
		Ratios = {
			3, -- 1, R
			3, -- 2, D1
			2, -- 3, D2
			1.5, -- 4, D3
			1, -- 5, D4,
			0.5 -- 6, D5
		},
		FACTOR = 3.75,
		DiffRatio = 0.65,
		CurrentGear = 2,
		MIN_GEAR_INDEX = 2,
		MAX_GEAR_INDEX = 6,
		REVERSE_GEAR_INDEX = 1
	}


	local ENGINE_IDLE_RPM = 800;

	local ENGINE_MAX_RPM = 8000;

	-- get reference to the script
	local CarDriver = LUA.script;

	-- serialized fields

	--- Front Right Wheel collider  
	local wheelFR = SerializedField("Wheel FR", WheelCollider);

	--- Front Left Wheel collider
	local wheelFL = SerializedField("Wheel FL", WheelCollider);

	--- Back Right Wheel collider
	local wheelBR = SerializedField("Wheel BR", WheelCollider);

	--- Back Left Wheel collider
	local wheelBL = SerializedField("Wheel BL", WheelCollider);


	--#region internal objects 

	--- @enum EngineState
	local EngineState = {
		--- Engine is turned off
		Off = 0,
		--- engine is starting up
		Startup = 1,
		--- Engine is idling
		Idle = 2,
		--- Engine is throttling, creating torque
		Acceleration = 3,
	}


	--- @class CarEngine
	--- @field rpm number the current RPM of the engine
	--- @field state EngineState current engine state
	--- @field startTime number the start time of the engine
	local CarEngine = {};

	--- Calculate the current engine state
	---@param throttle number current throttle
	---@param speed number current speed
	function CarEngine.CalculateCurrentEngineState(self, throttle, speed)
		if self.state == EngineState.Off or self.state == EngineState.Startup then
			self.rpm = 0;
			if self.state == EngineState.Startup and  Time.time - self.startTime > 3 then
				self.state = EngineState.Idle;
			end
			return;
		end

		local wheel_rpm = (speed * 60)/(2 * math.pi * wheelBL.radius);

		local wheelRPM = math.abs(wheel_rpm) * ((GEAR_BOX.FACTOR * GEAR_BOX.Ratios[GEAR_BOX.CurrentGear]) + GEAR_BOX.DiffRatio);

		if wheelRPM > ENGINE_MAX_RPM * 0.7 then
			-- shift to next gear
			if GEAR_BOX.CurrentGear < GEAR_BOX.MAX_GEAR_INDEX then
				GEAR_BOX.CurrentGear = GEAR_BOX.CurrentGear + 1
			end
		end
		if wheelRPM < ENGINE_MAX_RPM * 0.5 then
			-- shift to lower gear
			if GEAR_BOX.CurrentGear > GEAR_BOX.MIN_GEAR_INDEX then
				GEAR_BOX.CurrentGear = GEAR_BOX.CurrentGear - 1;
			end
		end


		local targetRPM = wheelRPM + Mathf:Lerp(0,ENGINE_MAX_RPM / 16, math.abs(throttle));

		self.rpm = Mathf:MoveTowards(self.rpm, targetRPM, 100);

		if throttle <= 0.05 then
			self.state = EngineState.Idle;
		else
			self.state = EngineState.Acceleration;
		end

		if self.rpm <= ENGINE_IDLE_RPM then
			self.rpm = ENGINE_IDLE_RPM;
		end

		if self.rpm > ENGINE_MAX_RPM then
			self.rpm = ENGINE_MAX_RPM;
		end
	end

	---The engine RPM vs Torque curve
	---@param engineRPM number current Engine RPM
	---@return number the torque that engine generates in gived RPM
	function  CarEngine:GetEngineTorque(engineRPM)
		local rpm = Mathf:Clamp(engineRPM / ENGINE_MAX_RPM, 0, 1);
		return Mathf:Clamp(math.sin(math.sqrt(rpm) * math.pi) * 0.58 + math.sin(rpm*rpm*math.pi) * 0.58 + 0.095, 0, 1);
	end

	--- Creates a new Car Engine Object
	---@return CarEngine
	function CarEngine:New()
		return {
			rpm = 0,
			state = EngineState.Off,
			startTime = 0
		}
	end
	--#endregion
	

	--- Car's Rigidbody
	local rigidbody = SerializedField("Rigidbody", Rigidbody);

	--- Steering wheel gameobject
	local steeringWheel = SerializedField("Steering Wheel", GameObject);

	--- Speed Dial indicator GameObject
	local speedDial = SerializedField("Speed Dial", GameObject);

	--- Engine RPM indicator GameObject
	local engineRPMDial = SerializedField("Engine RPM Dial", GameObject);

	local localControlIndicator = SerializedField("LocalControl", GameObject);

	--- local gameobject which is used as a mean of synchronizing the steering, throttle and direction of the car based on it's local position, which synchronized using 
	local syncObject = SerializedField("Local Synchronized Object", Transform);

	--- position of car's ideal center of mass 
	local centerOfMass = SerializedField("Center Of Mass", Transform);

	--- the MLStation component
	local station = SerializedField("Station", MLStation);

	--- @type number For Desktop Mode only. How much holding the W or S button changes the throttle per frame
	local THROTTLE_FACTOR = SerializedField("THROTTLE FACTOR", Number);

	--- @type number For Desktop Mode Only. How much holding A or D buttons changes the steering value per frame
	local STEERING_FACTOR = SerializedField("STEERING FACTOR", Number);

	--- @type number The max engine torque, modified by the engine's RPM vs Torque curve and apply to wheel after gear box reduction factors.
	local MOTOR_MAX_TORQUE = SerializedField("MOTOR MAX TORQUE", Number);

	--- @type number Max steering angle.
	local STEERING_ANGLE_MAX = SerializedField("STEERING ANGLE MAX", Number);

	--- @type number Maximum breaking torque per front wheels.
	local MAX_BREAK_TORQUE = SerializedField("MAX BREAK TORQUE", Number);

	--- @type boolean Use Ackerman steering geometry for steering angle calculation.
	local useAckerman = SerializedField("Use Ackerman Steering Model", Bool);

	--- @type number Handbreak torque to apply to wheels.
	local handBreakTorque = SerializedField("Hand break torque", Number);

	--- @type boolean use cuved steering instead of linear steering. 
	local useCurvedSteeringInVR = SerializedField("VR Curved steering input", Bool);

	--- local gameobject which is used as a mean of synchronizing the steering, throttle and direction of the car based on it's local position, which synchronized using 
	local minimapMarker = SerializedField("Minimap Marker Object", GameObject);

	local engineAudio = {
		--- Audio for engine startup
		startup = SerializedField("Engine Startup Audio", AudioSource),

		--- Audio for engine idle
		idle = SerializedField("Engine Idle Audio", AudioSource),

		--- Audio for engine acceleration
		acceleration = SerializedField("Engine Acceleration Audio", AudioSource),

		--- Audio for engine drive
		drive = SerializedField("Engine Drive Audio", AudioSource),

		--- max volume for idle audio
		idleMaxVoulme = 0,

		--- max volume for acceleration audio
		accelerationMaxVolume = 0,

		--- max volume for engine drive audio
		driveMaxVolume = 0,
	}
 
	local envAudio = {
		--- Audio Source for wind noise
		wind = SerializedField("Wind Audio", AudioSource);
	}

	--- the noise of impact to car
	local impact = SerializedField("Impact Noise", AudioClip);

	--- text showing the car's current gear
	local gearIndicator = SerializedField("Gear Indicator", Text);

	function engineAudio.ShutdownAllAudio(self)
		self.acceleration.volume = 0;
		self.drive.volume = 0;
		self.idle.volume = 0;
	end
	--- the direction of cars movement. 1 indicates foreward, -1 backward
	local direction = 1;

	--- the current throttle amount [-1,1]
	local throttle = 0;

	--- the current steering amount [-1,1], positive is right
	local steering = 0;

	--- the current break amount [0,1]. 1 is full break. 0: no breaking
	local breaks = 0;
	
	--- the speed of the car at current frame
	local speed = 0;

	--- the simple moving average of the speed.
	local speedSMA = 0;

	--- sample size to calculate speed SMA
	local speedSMASamplesSize = 10;

	--- the last few frame speeds of the car. Used for calculation of speedSMA. Length of speedSMASamplesSize
	local previousSpeeds = {};

	--- the car's wheel base (Distance between front and back wheels)
	local wheelBase = 0;

	--- the car's track (Distance between left and right wheels)
	local track = 0;

	--- car's turning radius calculated by base, track and max steering angle
	local turningRadius = 0;

	--- threshold for desktop mode key 
	local DM_KEY_TRESHOLD = 0.5;

	--- minimum speed where the direction change can happen
	local MIN_SPEED_TO_CHANGE_DIRECTION = 1;

	--- maximum throttle when reversing
	local MAX_REVERSE_THROTTLE = -0.8;

	--- is the car controlled by current client's local player?
	local underLocalPlayerControl = false;

	local debugText = SerializedField("Debug UI", Text);

	--- vehicles last position.
	local lastPost = Vector3.zero;

	

	---@type CarEngine current engine state
	local carEngine = nil;

	local function OnPlayerEnterStation()
		engineAudio.startup.Play();
		carEngine.state = EngineState.Startup;
		carEngine.startTime = Time.time;
		minimapMarker.SetActive(true);
	end

	local function OnPlayerLeftStation()
		carEngine.state = EngineState.Off;
		minimapMarker.SetActive(false);
	end

	
	--- Handles player input when in desktop mode for each frame
	---@param input UserInput
	local function HandleDesktopModeInput(input)
		
		-- handle throttle
		if input.KeyboardMove.y > DM_KEY_TRESHOLD then
			
			throttle = throttle + THROTTLE_FACTOR;
			if throttle > 1 then
				-- limit throttle max to 1
				throttle = 1;
			end

			if direction > 0 then
				-- breaking behavior when going foreward	
				if throttle > 0 then
					breaks = 0;
				end
			else
				-- breaking behavior when going foreward
				if throttle > 0 then
					breaks = breaks + THROTTLE_FACTOR;
				end

				if breaks > 1 then
					-- limit breaking max to 1
					breaks = 1;
				end

				if speedSMA < NEAR_ZERO then
					throttle = 0;
					direction = - direction;
				end
			end
		elseif input.KeyboardMove.y < -DM_KEY_TRESHOLD then
			if direction > 0 then
				-- if going forward
				throttle = throttle - (THROTTLE_FACTOR * 2);
				if throttle < 0 then
					breaks = breaks + THROTTLE_FACTOR;
				end
				if throttle < -1 then
					-- limit throttle min to -1;
					throttle = -1;
				end
				if breaks > 1 then
					-- limit throttle max to 1;
					breaks = 1;
				end

				if speedSMA < MIN_SPEED_TO_CHANGE_DIRECTION then
					throttle = 0;
					direction = -direction;
				end
			else
				-- if going backward
				throttle = throttle - THROTTLE_FACTOR;
				if throttle < 0 then
					breaks = 0;
				end
				if throttle < MAX_REVERSE_THROTTLE  then
					-- limit reversing throttle
					throttle = MAX_REVERSE_THROTTLE;
				end
			end
		else
			throttle = throttle - (throttle / 2);
		end

		-- handle steering
		if input.KeyboardMove.x > DM_KEY_TRESHOLD then
			
			steering = steering + STEERING_FACTOR;
			if steering > 1 then
				-- limit steering max to 1
				steering = 1;
			end
		elseif input.KeyboardMove.x < -DM_KEY_TRESHOLD then
			steering = steering - STEERING_FACTOR;
			if steering < -1 then
				-- limit steering min to -1
				steering = -1;
			end
		else
			steering = steering - (steering / 20);
		end

		-- handle handbreak
		if input.Jump then
			wheelBL.brakeTorque = handBreakTorque;
			wheelBR.brakeTorque = handBreakTorque;
		else
			wheelBL.brakeTorque = 0;
			wheelBR.brakeTorque = 0;
		end
	end

	--- Handles player input when in VR Mode for each frame
	---@param input UserInput
	local function HandleVRModeInput(input)
		throttle = input.LeftControl.y;

		local steeringTarget = 0;

		if useCurvedSteeringInVR then
			-- curved steering input using tan
			steeringTarget = math.tan(input.RightControl.x / 0.685) * 0.113;
		else
			-- linear steering 
			steeringTarget = input.RightControl.x;
		end

		steering = Mathf:MoveTowards(steering, steeringTarget, 1.5 * Time.deltaTime);

		if direction > 0 then
			if throttle > NEAR_ZERO then
				breaks = 0;
			else
				breaks = math.abs(throttle);
				throttle = 0;
				if speedSMA < MIN_SPEED_TO_CHANGE_DIRECTION then
					direction = -direction;
				end
			end
		elseif direction < 0 then
			if throttle > NEAR_ZERO then
				breaks = math.abs(throttle);
				throttle = 0;
				if speedSMA > -MIN_SPEED_TO_CHANGE_DIRECTION then
					direction = -direction;
				end
			else
				if throttle < MAX_REVERSE_THROTTLE then
					throttle = MAX_REVERSE_THROTTLE;
				end
				breaks = 0;
			end
		end
	end

	--- Handles engine audio effects
	local function HandleEngineAudioEffects()
		
		if carEngine.state == EngineState.Off then
			engineAudio.ShutdownAllAudio(engineAudio);
		elseif carEngine.state == EngineState.Startup then
			engineAudio.acceleration.volume = 0;
			engineAudio.drive.volume = 0;
			engineAudio.idle.volume = 0;
		else
			-- true throttle means, what is actually being feed to engine.  
			local trueThrottle = 0;
			if direction >= 0 and throttle >= 0 then
				trueThrottle = Mathf:Clamp(throttle, 0,1);
			elseif direction < 0 and throttle < 0 then
				trueThrottle = Mathf:Clamp(math.abs(throttle), 0,1);
			end

			local rpmFactor = Mathf:InverseLerp(ENGINE_IDLE_RPM, ENGINE_MAX_RPM, carEngine.rpm);

			-- acceleration: only when hight throttling, pitchup with rpm. volume up with throttle. 
			engineAudio.acceleration.volume = trueThrottle;
			engineAudio.acceleration.pitch = Mathf:Lerp(0.8, 1.5, rpmFactor);
			-- idle: when engine is in idling. More audiable in lower rpms. pitch up with rpm and throttling   
			engineAudio.idle.pitch = Mathf:Lerp(1, 1.8, rpmFactor + throttle);
			engineAudio.idle.volume = Mathf:Lerp(1,0,rpmFactor);
			-- drive: depends on engine rpm. Becomes more audiable in higher rpms. pitch up with rpm 
			engineAudio.drive.pitch = Mathf:Lerp(0.5,1.5, rpmFactor);
			engineAudio.drive.volume = Mathf:Lerp(0.2,1, rpmFactor);
		end
	end


	local function HandleOtherAudioEffects()
		-- increment wind noise and pitch with speed
		local speedFactor = Mathf:InverseLerp(0,50,speedSMA);
		envAudio.wind.volume = Mathf:Lerp(0, 1, speedFactor);
		envAudio.wind.pitch = Mathf:Lerp(1,1.3, speedFactor);
	end

	
	-- start only called at beginning
	function CarDriver.OnEnable()
		-- calculate car's geometric values.
		wheelBase = Vector3:Distance(wheelBL.transform.position, wheelFR.transform.position);
		track = Vector3:Distance(wheelFL.transform.position, wheelFR.transform.position);
		local betaAngleRadian = (180 - (STEERING_ANGLE_MAX + 90)) * Mathf.Deg2Rad;
		turningRadius = (Mathf:Abs(Mathf:Tan(betaAngleRadian) * wheelBase)) + (track / 2);
		--Debug:Log(string.format("Turning Radius: %.2f with Beta of %0.2f and max angle of: %0.1f", turningRadius, betaAngleRadian, STEERING_ANGLE_MAX));

		-- set center of mass for rigidbody 
		rigidbody.centerOfMass = centerOfMass.localPosition;

		--- pre-initilize the previousSpeeds array.
		for i = 1, 10, 1 do
			previousSpeeds[i] = 0;
		end

		lastPost = CarDriver.transform.position;

		engineAudio.idleMaxVoulme = engineAudio.idle.volume;
		engineAudio.idle.volume = 0;
		engineAudio.accelerationMaxVolume = engineAudio.acceleration.volume;
		engineAudio.acceleration.volume = 0;
		engineAudio.driveMaxVolume = engineAudio.drive.volume;
		engineAudio.drive.volume = 0;
		station.OnPlayerSeated.Add(OnPlayerEnterStation);
		station.OnPlayerLeft.Add(OnPlayerLeftStation);
		carEngine = CarEngine:New();

		if station.IsOccupied then
			carEngine.state = EngineState.Idle;
		end
	end


	function CarDriver.Start()
		-- start audios
		engineAudio.idle.Play();
		engineAudio.acceleration.Play();
		engineAudio.drive.Play();
		envAudio.wind.Play();
	end

	-- update called every frame
	function CarDriver.Update()
		if station.IsOccupied then
			local player = station.GetPlayer();
			if player.isLocal then
				underLocalPlayerControl = true;
				local input = station.GetInput();
				if direction == 0 then
					direction = 1;
				end
				if MassiveLoop.IsInDesktopMode then
					-- desktop mode input
					HandleDesktopModeInput(input);
				else
					-- VR mode input
					HandleVRModeInput(input);
				end
			else
				underLocalPlayerControl = false;
			end

		else
			underLocalPlayerControl = false;
		end

		-- handle car's state synchronization
		if underLocalPlayerControl then
			-- the car is in current local player's control.
			-- use x value as throttle, y value as steering, and z value as direction
			syncObject.localPosition = Vector3(throttle, steering, direction);
		else
			-- the car is controlled by someone else. 
			-- we can read the local position of the object to determine the synchronized values for throttle, steering and direction

			local localPos = syncObject.localPosition;
			throttle = localPos.x;
			steering = localPos.y;
			direction = localPos.z;
		end

		
		


		-- apply steering to steeringWheel rotation. This is for looks only. TODO: Work on actual interactable steeringWheel
		-- here we assume that the 4 full rotation of steeringWheel required for full steering, hence the steering angle multiplied by 4
		steeringWheel.transform.localRotation = Quaternion:Euler(-steering * STEERING_ANGLE_MAX * 4, -90, 0);

		-- apply speed to speedDial rotation
		speedDial.transform.localRotation = Quaternion:Euler(0, Mathf:LerpUnclamped(-42,71, math.abs(speedSMA/100) * 2.23694), 0);

		-- apply engine RPM to the RPM indicator
		engineRPMDial.transform.localRotation = Quaternion:Euler(0,Mathf:Lerp(-135,135,Mathf:InverseLerp(0, ENGINE_MAX_RPM, carEngine.rpm)),0);

		-- apply current gear to gear indicator 
		if direction < 0 then
			gearIndicator.text = "R";
		else
			gearIndicator.text = string.format("D%d", GEAR_BOX.CurrentGear - 1);
		end

	end

	function CarDriver.FixedUpdate()

		if underLocalPlayerControl then
			-- calculate speed using one the front wheels rpm
			speed = (wheelFL.rpm * wheelFL.radius * math.pi * 2) * 0.06; -- m/s
		else
			-- calculate speed based on car's position.
			speed = Vector3:Distance(lastPost, CarDriver.transform.position) / Time.fixedDeltaTime; -- m/s
			lastPost = CarDriver.transform.position;
		end

		-- set the sample of speed at current physics frame
		previousSpeeds[Time.frameCount % speedSMASamplesSize] = speed;

		-- sum-up the speed samples value
		local samplesSum = 0;

		for index, value in ipairs(previousSpeeds) do
			samplesSum = samplesSum + value;
		end

		-- calculate speed Simple Moving Average
		speedSMA = samplesSum / speedSMASamplesSize;

		-- show local player indicator
		localControlIndicator.SetActive(underLocalPlayerControl);
		
		-- apply physical properties if local player is under control

		debugText.text = "Engine RPM: " .. string.format("%d", carEngine.rpm) .. "\n" .. "Current Gear: " .. string.format("%d", GEAR_BOX.CurrentGear) .. "\n" .. string.format("Throttle: %.3f", throttle);
		debugText.text = debugText.text .. string.format("Direction: %d", direction) .. "\n" .. string.format("Engine State: %s", tostring(carEngine.state));

		if underLocalPlayerControl then
			 

			-- free rolling auto direction change 
			if speedSMA > MIN_SPEED_TO_CHANGE_DIRECTION then
				if (direction > 0 and speedSMA < 0) or (direction < 0 and speedSMA > 0) then
					direction = -direction;
				end
			end

			-- apply motor torque or breaking torque to the wheels. 
			if breaks < NEAR_ZERO then
				wheelFL.brakeTorque = 0;
				wheelFR.brakeTorque = 0;
				wheelBL.brakeTorque = 0;
				wheelBR.brakeTorque = 0;
				if (throttle > 0 and direction > 0) or (throttle < 0 and direction < 0) then
					-- apply motor torque to back wheels. 
					-- TODO: apply differential based on steering? Not sure if required because this is torque, not final rotation. 

					local rpmRelativeT = CarEngine:GetEngineTorque(carEngine.rpm);
					local wheelTorque = throttle * rpmRelativeT * MOTOR_MAX_TORQUE * (GEAR_BOX.FACTOR * GEAR_BOX.Ratios[GEAR_BOX.CurrentGear]) / 2;
					debugText.text = debugText.text .. string.format("rpm: %.4f", rpmRelativeT);
					wheelBL.motorTorque = wheelTorque;
					wheelBR.motorTorque = wheelTorque;
				else
					wheelBL.motorTorque = 0;
					wheelBR.motorTorque = 0;
				end
			else
				-- more breaking torque with higher speeds
				local breaking = breaks * MAX_BREAK_TORQUE + speedSMA * 2;
				wheelFL.brakeTorque = breaking;
				wheelFR.brakeTorque = breaking;
				wheelBL.brakeTorque = breaking/2;
				wheelBR.brakeTorque = breaking/2;
			end
		else
			wheelBL.brakeTorque = 0;
			wheelBR.brakeTorque = 0;
			wheelFL.brakeTorque = 0;
			wheelFR.brakeTorque = 0;
		end

		if useAckerman then
			-- use Ackerman steering geometry
			local ackAngleLeft = 0;
			local ackAngleRight = 0;

			--local _steering = steering * (max_steering/STEERING_ANGLE_MAX);
			local halfTrack = track / 2;
			if steering > 0 then
				ackAngleLeft = Mathf.Rad2Deg * Mathf:Atan(wheelBase / (turningRadius + halfTrack)) * steering/2;
				ackAngleRight = Mathf.Rad2Deg * Mathf:Atan(wheelBase / (turningRadius - halfTrack)) * steering/2;
			elseif steering < 0 then
				ackAngleLeft = Mathf.Rad2Deg * Mathf:Atan(wheelBase / (turningRadius - halfTrack)) * steering/2;
				ackAngleRight = Mathf.Rad2Deg * Mathf:Atan(wheelBase / (turningRadius + halfTrack)) * steering/2;
			else
				ackAngleRight = 0;
				ackAngleLeft = 0;
			end

			wheelFR.steerAngle = ackAngleRight;
			wheelFL.steerAngle = ackAngleLeft;
		else
			-- use parallel steering geormetry
			wheelFR.steerAngle = steering * STEERING_ANGLE_MAX;
			wheelFL.steerAngle = steering * STEERING_ANGLE_MAX;
		end


		if underLocalPlayerControl then
			-- calculate current engine state based on one of rear wheels rotation (powertrain feedback loop)
			CarEngine.CalculateCurrentEngineState(carEngine, throttle, 2 * math.pi * wheelBL.radius * (wheelBL.rpm / 60));
		else
			-- calculate current engine state based on speed SMA
			CarEngine.CalculateCurrentEngineState(carEngine, throttle, speedSMA);
		end
		
		
		HandleEngineAudioEffects();
		HandleOtherAudioEffects();

		
	end

	function CarDriver.OnCollisionEnter(colision)
		-- apply collision sfx/fx 
		if colision ~= nil then
			local contact = colision.GetContact(0);
			if contact ~= nil then
				AudioSource:PlayClipAtPoint(impact, contact.point, colision.impulse.magnitude/10);
			end
		end
	end

	function CarDriver.OnDisable()
		station.OnPlayerSeated.RemoveAllListeners();
		station.OnPlayerLeft.RemoveAllListeners();
	end
end