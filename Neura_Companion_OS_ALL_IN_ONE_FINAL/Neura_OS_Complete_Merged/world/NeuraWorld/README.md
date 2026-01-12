# NeuraWorld (Unity)

This is a **skeleton Unity project** with Neura bridge + locomotion + prop interaction + cinematics + emotion lighting scripts already placed under `Assets/Scripts/`.

## Setup
1. Open this folder in Unity 2021 LTS+.
2. Import packages if prompted (Cinemachine, Timeline).
3. Create a GameObject named `NeuraBridge` and attach `AndroidBridgeReceiver` + `BridgeRouter`.
4. Add props to the scene and attach `NeuraPropInteractable` with matching `propId` values.

## Build
- **Android:** Export as Library (unityLibrary) for the Android shell.
- **Windows:** Build Standalone Windows x64.
