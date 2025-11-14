# Massive-Loop-CSharp-Car
This is an implementation of an arcadey style vehicle controller system that allows both VR and Desktop players to drive in Massive Loop!


# Car Driver System  

*A fully simulated, VR-ready and desktop-compatible vehicle controller for the MassiveLoop SDK.*

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [How the System Works](#how-the-system-works)
  - [Engine Simulation](#engine-simulation)
  - [Gearbox Logic](#gearbox-logic)
  - [Steering System](#steering-system)
  - [Networking and Sync](#networking-and-sync)
  - [Audio Simulation](#audio-simulation)
- [Control Schemes](#control-schemes)
  - [Desktop Mode Controls](#desktop-mode-controls)
  - [VR Mode Controls](#vr-mode-controls)
- [UI & Visual Systems](#ui--visual-systems)
- [Vehicle Entry & Exit](#vehicle-entry--exit)
- [Setup Instructions](#setup-instructions)
- [File Reference](#file-reference)

---

## Overview

This is a feature-rich vehicle driving system built for the MassiveLoop (ML) SDK. It supports:

- **Realistic wheel collider driving**
- **Engine RPM simulation**
- **Automatic gear shifting**
- **VR and Desktop input modes**
- **Networking sync for remote drivers**
- **Dynamic audio blending**
- **Physical steering wheel animations**
- **Speedometer & Tachometer needles**
- **Reverse gear logic**

The main logic is contained in the script:

`CarDriver_CSharp.cs`

---

## Features

###   Real engine model  

- Idle, Startup, Acceleration states  
- RPM computed from wheel RPM  
- Torque curve based on two combined sine waves  
- Automatic up/down shifting based on engine load

###   Two distinctive input modes  

- **Desktop Mode:** keyboard driving with smoothed steering  
- **VR Mode:** analog control using left & right VR controller joysticks

###   Physics-accurate steering  

- Optional **Ackerman steering geometry**  
- Adjustable steering curves for VR

###   Network synchronized  

The car supports:

- Local driver authoritative control  
- Sync of throttle, steering, direction through a `syncObject` transform  
- Remote players see the correct movement & wheel rotation

###   Full audio stack  

The script contains:

- Engine startup audio  
- Idle audio  
- Acceleration audio  
- Driving audio  
- Wind audio based on actual speed  

---

## How the System Works

### Engine Simulation

The engine is represented by a nested `CarEngine` class.  
It computes:

- **RPM from wheel rotation**
- Adds throttle & torque load on top  
- Smoothly transitions between states:
  - **Off**
  - **Startup** (3-second sequence)
  - **Idle**
  - **Acceleration**

RPM clamps between:

- Idle: `800 rpm`  
- Max: `8000 rpm`

The torque curve uses a custom mathematical blend of sine functions to create realistic acceleration responsiveness.

---

### Gearbox Logic

Gears are simulated through an array of ratios:

```csharp
float[] gearRatios = { 3f, 3f, 2f, 1.5f, 1f, 0.5f };
```

The script automatically shifts:

- **Up** when near high RPM  
- **Down** when RPM drops too low  

Reverse gear uses index **1**.

Gear indicator displays:

- `D1` → `D5`  
- `R` for reverse

---

### Steering System

The car supports two steering modes:

#### 1. Ackerman Steering (realistic)

Front wheels turn at slightly different angles depending on radius.

#### 2. Simple Steering

Both wheels turn the same amount.

VR steering optionally uses a *curved* response:

```csharp
steeringTarget = Mathf.Tan(input.RightControl.x / 0.685f) * 0.113f;
```

to improve fine control.

---

### Networking and Sync

A small `syncObject` transform encodes:

```text
x = throttle  
y = steering  
z = direction (1 = forward, -1 = reverse)
```

- When **local player** is seated → write to `syncObject`  
- When **remote player** is watching → read from `syncObject`  

This ensures identical behavior across clients in a MassiveLoop multiplayer world.

---

### Audio Simulation

Engine audio blends dynamically:

- **Idle Volume** decreases as RPM rises  
- **Drive Audio** increases with RPM  
- **Acceleration Audio** increases with throttle  
- **Wind Audio** increases with speed  

Pitch and volume adjustments create continuous engine progression.

---

## Control Schemes

### Desktop Mode Controls

| Action                         | Control                                             |
| ------------------------------ | --------------------------------------------------- |
| **Getting in**                 | Look at the Seat and Press `R`                      |
| **Getting Out**                | Press `R` While in the car                          |
| **Throttle (Drive Forward)**   | `W` / Up input (`KeyboardMove.y > 0.5`)             |
| **Reverse / Brake**            | `S` / Down input (`KeyboardMove.y < -0.5`)          |
| **Steering Left**              | `A` (`KeyboardMove.x < -0.5`)                       |
| **Steering Right**             | `D` (`KeyboardMove.x > 0.5`)                        |
| **Handbrake**                  | `Space` (`Jump`)                                    |
| **Automatic Direction Switch** | System-controlled when coming to a stop + reversing |

Steering automatically recenters when no input is applied.  
Throttle smoothly ramps up and down.

---

### VR Mode Controls

| Action                      | VR Input                                                   |
| --------------------------- | ---------------------------------------------------------- |
| **Getting in**              | Point at the seat with one of your hands and Press `A`     |
| **Getting Out**             | Press `A`  When Inside the vehicle                         |
| **Throttle (forward/back)** | Left Thumbstick `Y` (`input.LeftControl.y`)                |
| **Steering**                | Right Thumbstick `X` (`input.RightControl.x`)              |
| **Curved Steering Option**  | Uses tangent curve when `useCurvedSteeringInVR` is enabled |
| **Reverse**                 | Push throttle opposite direction until car stops           |
| **Handbrake / Braking**     | Implicit through throttle & direction logic                |

VR mode offers more analog control and fluid steering compared to desktop mode.

---

## UI & Visual Systems

### Steering Wheel Animation

```csharp
steeringWheel.transform.localRotation = Quaternion.Euler(
    -steering * STEERING_ANGLE_MAX * 4, 
    -90, 
    0
);
```

### Speedometer Needle  

Indicator rotates based on *smoothed speed* (SMA of last N speed samples).

### RPM Gauge  

Reads actual simulated engine RPM and animates the tachometer needle.

### Player Thumbnails  

When entering the vehicle, the ML player thumbnail is loaded and applied to decals:

```csharp
currentDriver.LoadPlayerThumbnail((texture) =>
{
    if (texture != null)
    {
        Decal_1.material.mainTexture = texture;
        if (Decal_2 != null)
        {
            Decal_2.material.mainTexture = texture;
        }
    }
});
```

---

## Vehicle Entry & Exit

### When Player Enters

- Engine enters `Startup` state  
- Physics drag removed  
- Driver stored in `currentDriver`  
- Player thumbnail applied to decals  

### When Player Exits

- Throttle reset to 0  
- Handbrake applied to all wheels  
- Engine set to `Off`  
- Rigidbody velocity reset to zero  
- `currentDriver` cleared  

---

## Setup Instructions (If You want to only use the script and use a different, custom car)

1. Add **`CarDriver_CSharp.cs`** to your vehicle GameObject.
2. Assign the following fields in the Inspector:
- **Wheel Colliders**: `wheelFR`, `wheelFL`, `wheelBR`, `wheelBL`
- **Rigidbody**: `Car_RB`
- **Steering Wheel**: `steeringWheel`
- **Speed Dial**: `speedDial`
- **Engine RPM Dial**: `engineRPMDial`
- **Center of Mass**: `centerOfMass`
- **ML Station**: `station`
- **Sync Object**: `syncObject` (empty child used for network sync)
- **Audio Sources**: `engineStartupAudio`, `engineIdleAudio`, `engineAccelerationAudio`, `engineDriveAudio`, `windAudio`
- (Optional) **Decals**: `Decal_1`, `Decal_2` for player thumbnail projection
3. Ensure your scene has:
   - Proper ML setup (Our MassiveLoop SDK, world descriptor, and spawn point)
   - The car’s wheels positioned correctly for the colliders
4. Upload your world or locally build and run through our SDK and sit in the car’s station to take control.

---

---
## Setup Instructions (If You want to use the given car)

1. Ensure your scene has:
   - Proper ML setup (Our MassiveLoop SDK, world descriptor, and spawn point)
   - The car’s wheels positioned correctly for the colliders
2. Drag and drop the ML_Go-Kart asset into your world.
3. Upload your world or locally build and run through our SDK and sit in the car’s station to take control.
4. Have fun! 

---

## File Reference

- **CarDriver_CSharp.cs**  
  Main script containing:
  - Engine simulation & gearbox logic  
  - Input handling for VR & Desktop  
  - Wheel collider drive system  
  - Audio blending  
  - Network sync through `syncObject`  
