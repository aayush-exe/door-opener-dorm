# Door opener for dorms via ESP32 Bluetooth and iOS app
Open your dorm door (or any door) with just your phone! No more locking yourself out

![Screenshot 2025-05-04 at 1 41 25 PM](https://github.com/user-attachments/assets/a3234485-bd1f-4a3c-9957-ef81ef98077c)

Have a club/shared room/any shared space and want to know when it's open? This simple device detects when a door is opened and closed, both with toggle and with live state modes.
Uses a limit switch (can be changed to other detection methods like beam breakers w/ simple coding) and a Wi-Fi powered Arduino or ESP32 (I used Arduino Nano ESP32 in this)

I was inspired to make this project as my project team's lab was notorious for being left shut with no update from anyone. Thanks to this invention I always know when I can show up

-> toggle: door state toggled with every limit switch open/close

-> live state: status open when limit switch open, closed when limit switch closed

# BUILD INSTRUCTIONS HERE!

# iOS app instructions 
It costs $99/yr to put this on the app store so thats not very feasible for this small project, but you can still use the app!
(i didnt make an Android app but it shouldn't be that hard to make since the interface the ESP32 uses is standardized)
1. Download the latest version of Xcode
2. Open Xcode and open the "xcodeproj" file (in the folder named "dooropener-simple" in this GitHub)
3. Plug in your iphone to your computer and follow [the instructions here](https://developer.apple.com/documentation/xcode/running-your-app-in-simulator-or-on-a-device) to get this app running on your device
4. to actually use the app, change the device name and PIN in the app textboxes to whatever was set in the Arduino code

Follow for more tips
