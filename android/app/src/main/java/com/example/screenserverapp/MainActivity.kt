package com.example.screenserverapp

import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.viewinterop.AndroidView
import com.example.screenserverapp.ui.theme.ScreenServerAppTheme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import okhttp3.*
import okio.ByteString
import org.json.JSONObject
import org.webrtc.*

import java.util.concurrent.TimeUnit

class MainActivity : ComponentActivity() {
    // --- WebSocket state
    private var ws: WebSocket? = null
    private lateinit var httpClient: OkHttpClient

    // --- WebRTC state
    private var eglBase: EglBase? = null
    private var pcFactory: PeerConnectionFactory? = null
    private var peerConnection: PeerConnection? = null
    private var remoteRenderer: SurfaceViewRenderer? = null

    // ICE servers (público Google STUN)
    private val iceServers = listOf(
        PeerConnection.IceServer.builder("stun:stun.l.google.com:19302").createIceServer()
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        setContent {
            ScreenServerAppTheme {
                var status by remember { mutableStateOf("Idle") }
                var lastMsg by remember { mutableStateOf<String?>(null) }
                val scope = rememberCoroutineScope()

                // ⚠️ AJUSTA para o IP do teu Mac
                val signalingUrl = "ws://192.168.1.249:8080"

                // Inicializar WebRTC quando a UI monta
                LaunchedEffect(Unit) {
                    status = "Init WebRTC..."
                    initWebRtc()
                    status = "Connecting signaling..."
                    connectSignaling(
                        signalingUrl = signalingUrl,
                        onStatus = { status = it },
                        onJson = { json ->
                            lastMsg = json.toString()
                            handleSignaling(json)
                        }
                    )
                }

                DisposableEffect(Unit) {
                    onDispose {
                        try { ws?.close(1000, "bye") } catch (_: Throwable) {}
                        cleanupWebRtc()
                    }
                }

                Scaffold(modifier = Modifier.fillMaxSize()) { innerPadding ->
                    Column(Modifier.padding(innerPadding)) {
                        Text("Signaling: $status")
                        if (lastMsg != null) Text("Última mensagem: $lastMsg")

                        // Botão ping (debug)
                        Button(onClick = {
                            scope.launch(Dispatchers.IO) {
                                val ping = JSONObject()
                                    .put("type","ping")
                                    .put("from","android")
                                    .put("ts", System.currentTimeMillis()/1000.0)
                                ws?.send(ping.toString())
                            }
                        }) { Text("Enviar ping") }

                        // Render do vídeo remoto (WebRTC)
                        AndroidView(
                            factory = { ctx ->
                                SurfaceViewRenderer(ctx).apply {
                                    remoteRenderer = this
                                    eglBase?.eglBaseContext?.let { init(it, null) }
                                    setEnableHardwareScaler(true)
                                    setMirror(false)
                                }
                            },
                            update = { /* nada */ }
                        )
                    }
                }
            }
        }
    }

    // ----------------------------
    // Signaling (WebSocket)
    // ----------------------------
    private fun connectSignaling(
        signalingUrl: String,
        onStatus: (String) -> Unit,
        onJson: (JSONObject) -> Unit
    ) {
        httpClient = OkHttpClient.Builder()
            .pingInterval(20, TimeUnit.SECONDS)
            .connectTimeout(10, TimeUnit.SECONDS)
            .build()

        val req = Request.Builder().url(signalingUrl).build()
        ws = httpClient.newWebSocket(req, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                onStatus("Connected")
                val hello = JSONObject().put("type","hello").put("role","android")
                webSocket.send(hello.toString())

                // Diz ao Mac que estamos prontos para receber Offer
                webSocket.send(JSONObject().put("type","android-ready").toString())
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                runCatching { JSONObject(text) }
                    .onSuccess(onJson)
                    .onFailure { Log.w("Signaling", "JSON parse fail: $text") }
            }

            override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                Log.i("Signaling", "BIN: ${bytes.size} bytes")
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                onStatus("Closed ($code) $reason")
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, r: Response?) {
                onStatus("Error: ${t.message}")
                Log.e("Signaling","WS fail: ${t.message}", t)
            }
        })
    }

    // ----------------------------
    // Mensagens de signaling
    // ----------------------------
    private fun handleSignaling(msg: JSONObject) {
        when (msg.optString("type")) {
            "offer" -> {
                // Recebemos SDP Offer do Mac
                val sdp = msg.optString("sdp", "")
                if (sdp.isNotEmpty()) {
                    ensurePeerConnection()
                    peerConnection?.setRemoteDescription(
                        SimpleSdpObserver("setRemoteDescription(offer)"),
                        SessionDescription(SessionDescription.Type.OFFER, sdp)
                    )
                    // Criar e enviar Answer
                    peerConnection?.createAnswer(object : SdpObserver by SimpleSdpObserver("createAnswer") {
                        override fun onCreateSuccess(desc: SessionDescription) {
                            peerConnection?.setLocalDescription(
                                SimpleSdpObserver("setLocalDescription(answer)"),
                                desc
                            )
                            // Enviar answer pelo signaling
                            val answer = JSONObject()
                                .put("type", "answer")
                                .put("sdp", desc.description)
                                .put("role", "android")
                            ws?.send(answer.toString())
                        }
                    }, MediaConstraints())
                }
            }
            "ice" -> {
                // Candidato ICE vindo do Mac
                val sdpMid = msg.optString("sdpMid")
                val sdpMlineIndex = msg.optInt("sdpMLineIndex", -1)
                val candidate = msg.optString("candidate")
                if (sdpMid != null && sdpMlineIndex >= 0 && candidate.isNotEmpty()) {
                    ensurePeerConnection()
                    val ice = IceCandidate(sdpMid, sdpMlineIndex, candidate)
                    peerConnection?.addIceCandidate(ice)
                }
            }
            // debug
            "ping", "hello-ack" -> { /* já viste a funcionar */ }
        }
    }

    // ----------------------------
    // WebRTC: init / PC / render
    // ----------------------------
    private fun initWebRtc() {
        // Inicialização global
        val initOptions = PeerConnectionFactory.InitializationOptions.builder(this)
            .setEnableInternalTracer(false)
            .createInitializationOptions()
        PeerConnectionFactory.initialize(initOptions)

        // EGL para HW accel
        eglBase = EglBase.create()

        // Factory
        val opts = PeerConnectionFactory.Options()
        val encoderFactory = DefaultVideoEncoderFactory(
            eglBase!!.eglBaseContext,
            /* enableIntelVp8Encoder */ true,
            /* enableH264HighProfile */ true
        )
        val decoderFactory = DefaultVideoDecoderFactory(eglBase!!.eglBaseContext)

        pcFactory = PeerConnectionFactory.builder()
            .setOptions(opts)
            .setVideoEncoderFactory(encoderFactory)
            .setVideoDecoderFactory(decoderFactory)
            .createPeerConnectionFactory()
    }

    private fun ensurePeerConnection() {
        if (peerConnection != null) return

        val rtcConfig = PeerConnection.RTCConfiguration(iceServers).apply {
            sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
        }

        peerConnection = pcFactory?.createPeerConnection(
            rtcConfig,
            object : PeerConnection.Observer {
                override fun onIceConnectionReceivingChange(receiving: Boolean) {
                    Log.i("WebRTC", "ICE receiving: $receiving")
                }
                override fun onSignalingChange(newState: PeerConnection.SignalingState) { /* ... */ }
                override fun onIceConnectionChange(newState: PeerConnection.IceConnectionState) { /* ... */ }
                override fun onIceGatheringChange(newState: PeerConnection.IceGatheringState) { /* ... */ }

                override fun onIceCandidate(candidate: IceCandidate) {
                    // Enviar candidato para o Mac via signaling
                    val ice = JSONObject()
                        .put("type", "ice")
                        .put("sdpMid", candidate.sdpMid)
                        .put("sdpMLineIndex", candidate.sdpMLineIndex)
                        .put("candidate", candidate.sdp)
                        .put("role", "android")
                    ws?.send(ice.toString())
                }
                override fun onIceCandidatesRemoved(candidates: Array<IceCandidate>) {}

                // UNIFIED_PLAN: tracks chegam aqui
                override fun onTrack(transceiver: RtpTransceiver) {
                    val track = transceiver.receiver.track()
                    Log.i("WebRTC", "onTrack kind=${track?.kind()}")
                    if (track is VideoTrack && remoteRenderer != null) {
                        track.addSink(remoteRenderer)
                    }
                }

                // Compat Plan B (se o emissor enviar por stream)
                override fun onAddStream(stream: MediaStream) {
                    Log.i("WebRTC", "onAddStream(${stream.id}) videoTracks=${stream.videoTracks.size}")
                    if (stream.videoTracks.isNotEmpty() && remoteRenderer != null) {
                        stream.videoTracks[0].addSink(remoteRenderer)
                    }
                }

                override fun onRemoveStream(stream: MediaStream) {}
                override fun onDataChannel(dc: DataChannel) {}
                override fun onRenegotiationNeeded() {}
                override fun onAddTrack(receiver: RtpReceiver, streams: Array<out MediaStream>?) {}
            }
        )

        peerConnection?.addTransceiver(
            MediaStreamTrack.MediaType.MEDIA_TYPE_VIDEO,
            RtpTransceiver.RtpTransceiverInit(RtpTransceiver.RtpTransceiverDirection.RECV_ONLY)
        )
    }


    private fun cleanupWebRtc() {
        try { peerConnection?.close() } catch (_: Throwable) {}
        peerConnection = null
        try { remoteRenderer?.release() } catch (_: Throwable) {}
        remoteRenderer = null
        try { pcFactory?.dispose() } catch (_: Throwable) {}
        pcFactory = null
        eglBase?.release()
        eglBase = null
        try { PeerConnectionFactory.stopInternalTracingCapture() } catch (_: Throwable) {}
        try { PeerConnectionFactory.shutdownInternalTracer() } catch (_: Throwable) {}
    }
}

// ---------------------------------
// Helper para logs dos callbacks SDP
// ---------------------------------
private open class SimpleSdpObserver(private val tag: String) : SdpObserver {
    override fun onCreateSuccess(desc: SessionDescription) {
        Log.i("SDP/$tag", "onCreateSuccess: ${desc.type}")
    }
    override fun onSetSuccess() {
        Log.i("SDP/$tag", "onSetSuccess")
    }
    override fun onCreateFailure(error: String) {
        Log.e("SDP/$tag", "onCreateFailure: $error")
    }
    override fun onSetFailure(error: String) {
        Log.e("SDP/$tag", "onSetFailure: $error")
    }
}

@Preview(showBackground = true)
@Composable
fun PreviewMain() {
    ScreenServerAppTheme { Text("Preview") }
}
