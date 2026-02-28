# MyCamp 🗺️

MyCamp is an offline campus navigation application built using Flutter.  
It provides graph-based route calculation using JSON-defined nodes and edges, enabling structured navigation inside a campus environment.

---

## 📌 Features

- 🏫 Interactive campus map
- 📍 Graph-based navigation using Nodes & Edges
- 🧠 Shortest path calculation (Graph service layer)
- 💾 Offline data storage using Hive
- 👤 Admin user management screen
- 📦 Clean feature-based architecture

---

## 🏗 Architecture

The project follows a feature-based Clean Architecture structure:

lib/
│
├── core/
│ └── storage/
│
├── features/
│ ├── campus_navigation/
│ │ ├── data/
│ │ ├── domain/
│ │ └── presentation/
│ │
│ └── home/
│
└── main.dart


### Layers

- **Data Layer** → Models & local data services (JSON loading, storage)
- **Domain Layer** → Graph logic & business rules
- **Presentation Layer** → UI screens & coordinate mapping

---

## 🗂 Map Data Structure

Navigation is powered by JSON files:

- `nodes.json`
- `edges.json`
- `edges_with_geometry.json`
- `places.json`

These define the campus graph and routing structure.

---

## 🛠 Tech Stack

- Flutter
- Dart
- Hive (local storage)
- JSON-based graph structure

---

## 🚀 Getting Started

### 1️⃣ Clone the repository

```bash
git clone https://github.com/irfan28nizar/mycamp.git
cd mycamp
