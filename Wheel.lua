Namespace("brandonw_gokarts.yashar_ml_speeder");
do -- script NewLuaBehavior 
	
	-- get reference to the script
	local Wheel = LUA.script;

	--- The Wheel Collider
	local wheelCollider = SerializedField("Wheel Collider", WheelCollider);

	--- The Wheel Mesh object Parent
	local wheelObj = SerializedField("Wheel Object", GameObject);

	--- The Wheel Mesh object
	local innerWheelObj = SerializedField("Inner Wheel Object", GameObject);

	--- Screech noise
	local screechNoise = SerializedField("Screech Noise", AudioSource);

	--- Wheel Physics is calculated by local client?
	local isOwned = false;

	--- Wheel's last position
	local lastPos = Vector3.zero;

	--- Is Wheel slipping/Skiding? 
	local isSlipping = false;

	--- Flag for sending slipping event
	local slippingEventCheck = false;

	--- The name of the event to send the slipping evnet
	local SLIPPING_EVENT_NAME = "s";

	function Wheel.Start()
		lastPos = Wheel.transform.position;
		isOwned = Wheel.gameObject.Owner == Room:GetLocalPlayer();

		-- register the event for handling slipping 
		LuaEvents:AddLocal(Wheel, SLIPPING_EVENT_NAME, function (slip)
			isSlipping = slip;
		end);
	end

	-- update called every frame
	function Wheel.Update()
		-- move wheel object position and rotation based on the wheelCollider	
		local pos, rot = wheelCollider.GetWorldPose();
		wheelObj.transform.position = pos;
		wheelObj.transform.rotation = rot * Quaternion:Euler(0,-90,0);

		-- calculate speed
		local speed = (2 * math.pi * wheelCollider.radius) * (wheelCollider.rpm / 60);


		if not isOwned then
			--[[ 
				The wheel collider isrunning having a hard time calculating the wheel roll rotation when the physics is not calculated in the local client,
				so instead, we do a roll calculation based on wheel positional speed, radius and direction and apply it to the inner wheel object.  
			]]--

			-- distance moved since last frame
			local movementDist = Vector3:Distance(Wheel.transform.position, lastPos);
			
			-- speed 
			speed = movementDist / Time.deltaTime;
			
			-- find dot product to determine the rotation direction
			local dot = Vector3:Dot(Wheel.transform.parent.right, lastPos - Wheel.transform.position);
			local sign = 1;
			if dot < 0 then
				sign = -1;
			elseif dot == 0 then
				sign = 0;
			end

			-- rotational speed
			local wheelTurnsDeg =  (360 * movementDist / (2 * wheelCollider.radius * math.pi)) * sign;

			-- rpm = (wheelTurnsDeg * 0.0028 * 60 / Time.deltaTime);

			innerWheelObj.transform.Rotate(Vector3(0,0,wheelTurnsDeg), Space.Self);

			lastPos = wheelCollider.transform.position;
		end

		-- apply screech noise volume based on wheel speed.
		screechNoise.volume = Mathf:Lerp(0,1, Mathf:InverseLerp(0,20,speed));

		-- Play screechNoise is the wheel is slipping
		if isSlipping then
			if not screechNoise.isPlaying then
				screechNoise.Play();
			end
		else
			if screechNoise.isPlaying then
				screechNoise.Stop();
			end
		end
	end

	function Wheel.FixedUpdate()
		if isOwned then
			-- determine if the wheel is slipping
			local isWheelHittingGround, wheelHit = wheelCollider.GetGroundHit();
			if isWheelHittingGround then
				isSlipping = math.abs(wheelHit.forwardSlip) > 1 or math.abs(wheelHit.sidewaysSlip) > 0.2;
				
			else
				isSlipping = false;
			end

			if isSlipping then
				if not slippingEventCheck then
					LuaEvents:InvokeLocalNetwork(Wheel,SLIPPING_EVENT_NAME, EventTarget.Others, nil, true);
					slippingEventCheck = true;
				end
			else
				if slippingEventCheck then
					LuaEvents:InvokeLocalNetwork(Wheel,SLIPPING_EVENT_NAME, EventTarget.Others, nil, false);
					slippingEventCheck = false;
				end
			end
		end
	end

	function Wheel.OnBecomeOwner()
		isOwned = true;
	end

	function  Wheel.OnLostOwnership()
		isOwned = false;
	end
end