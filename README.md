# FeediSense 🐟📱

FeediSense is an IoT-enabled smart aquaculture management and automated feeding mobile application built with **Flutter**. It interfaces directly with an Arduino-based hardware system via GSM/SMS protocols to deliver real-time water quality tracking, smart sensor calibration, and remote feeding automation.

### 🔗 Hardware Subsystem Repository
> Arduino code, click below to view code.
* [View Hardware Prototype Repository](https://github.com/Cef777/FeediSense/blob/main/FeediSense_ArduinoCode.ino)

---

## 📸 Project Visuals

| Mobile Dashboard & Analytics | Hardware Prototype Integration |
| --- | --- |
| <img src="https://github.com/Cef777/FeediSense/blob/main/photo_2026-06-25_15-57-20.jpg" width="250" alt="App UI"/> | <img src="https://via.placeholder.com/350x500.png?text=Arduino+Prototype" width="350" alt="Hardware Setup"/> |
| *Real-time analytics plotting pH, DO, and Temp* | *Automated feeder prototype with load cells & sensors* |

---

## 🚀 Key Features & Engineering Highlights

* **Asynchronous Hardware-Software Sync (SMS Protocol):** Designed a robust cellular communication layer using the `another_telephony` framework. Handles state synchronization and manual dispensing command delivery (`CMD_0000`) without requiring internet dependency or Wi-Fi infrastructure.
* **Background Lifecycle Processing:** Implemented a persistent background message handler (`@pragma('vm:entry-point')`) to parse incoming hardware telemetry data, update app state, and dispatch local Android notifications even when the app is closed.
* **Custom Data Visualization & Analytics:** Built high-performance, dynamic time-series charts using Flutter’s `CustomPainter` to efficiently map historical sensor ranges (pH, Dissolved Oxygen, and Temperature) against risk thresholds.
* **Offline-First Architecture:** Integrated a local SQLite database caching layer using `sqflite` to buffer time-series data, store notification matrix logs, and preserve automation schedules across app restarts.
* **Normalized Data Export Engine:** Engineered a data processing pipeline that aggregates local relational records and compiles them into standardized CSV schemas using `share_plus`, enabling users to audit or share logs effortlessly.

---

## 🛠️ Tech Stack & Architecture

* **Frontend Framework:** Flutter (Dart)
* **Local Storage:** SQLite (`sqflite`)
* **Hardware Interfacing:** GSM/SMS Communication Gateway
* **State Management / Listeners:** ValueNotifier Architecture

### 📂 Directory Architecture
```text
lib/
├── main.dart                 # Application initialization & global themes
├── models.dart               # Data structures & multi-tiered risk evaluation engine
├── database_helper.dart      # Relational SQLite database management
├── sms_handler.dart          # Foreground/Background SMS listening & parsing logic
├── sms_config.dart           # SIM credentials & hardware routing properties
├── app_styles.dart           # Reusable UI component configurations & theme tokens
└── [screens/pages]           # Highly modular UI presentation views
