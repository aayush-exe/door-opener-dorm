# Door opener for dorms via ESP32 Bluetooth and iOS app
Open your dorm door (or any door) with just your phone! No more locking yourself out

This DIY project is pretty simple to build yourself and is relatively cheap (other than the servo which depends on which one you get). I've also listed complete build instructions below, but if you have any questions on the process you can contact me at @garage_goblins_ on instagram.

Thanks to [this project](https://www.instructables.com/DoorMe-Smartphone-Controlled-Keyless-Entry-For-Dor/) for the inspiration behind the project.

# Hardware instructions
You'll need:
- An Arduino/ESP32 capable of BLE and PWM signals (I used ESP32-WROOM)
- A power souce for the Arduino
- An iPhone for communicating to the device (no android app right now)
- A high-torque servo
- String/yarn
- A pulley/winch attachment for the servo [(here's the one I designed for this project)](https://cad.onshape.com/documents/61f1872a0c06c7a3b4d6bff2/w/ee628c89c2550850fde67cd9/e/5b565efe5ca670e395e86053)


# Arduino/ESP32 instructions
2. Open the .ino file in your Arduino IDE
3. Change the "DEVICE_NAME" and "AUTH_PIN" to whatever values you select (device_name is public, PIN is needed to open the door)
4. Change the servo PIN to whatever pin your Servo PWM will be connected to (make sure this pin is capable of PWM output)
5. Change the servo lock/unlock positions based on your door and installation (this controls where the "rest position" and "open position" of the servo is, so it'll depend on how you attach it to your door)
6. Upload the .ino file to your device and test it with the iOS app! you can also test if the arduino is working through an app called nRF Connect, which is something I also used while debugging.

# iOS app instructions 
It costs $99/yr to put this on the app store so thats not very feasible for this small project, but you can still use the app!
(i didnt make an Android app but it shouldn't be that hard to make since the interface the ESP32 uses is standardized)
1. Download the latest version of Xcode
2. Open Xcode and open the "xcodeproj" file (in the folder named "dooropener-simple" in this GitHub)
3. Plug in your iphone to your computer and follow [the instructions here](https://developer.apple.com/documentation/xcode/running-your-app-in-simulator-or-on-a-device) to get this app running on your device
4. to actually use the app, change the device name and PIN in the app textboxes to whatever was set in the Arduino code

if you have any questions about the project, you can ask me on the account @garage_goblins_ on instagram
Follow for more tips
