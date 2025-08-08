# Second-Display

> Transformar um tablet Android num segundo monitor para macOS (via cabo ou Wi-Fi).

## ✨ Visão geral
* **Servidor macOS** – captura o ecrã com ScreenCaptureKit, comprime em H.264 (VideoToolbox) e expõe via TCP/WebRTC.  
* **Cliente Android** – recebe o stream em tempo-real, descodifica com MediaCodec e devolve eventos de toque/rato.  
* **Protocolo** – mensagens Protobuf (`Frame`, `TouchEvent`) para manter contracto claro entre plataformas.

## 📁 Estrutura de pastas
```text
.
├─ android/       # Projecto Kotlin/Gradle do cliente Android
├─ macos/         # Swift Package + App host (Xcode)
├─ protocol/      # .proto partilhados (geram código Swift & Kotlin)
├─ docs/          # Diagramas, notas técnicas, testes de latência
└─ .vscode/second-display.code-workspace  # Workspace multi-root

