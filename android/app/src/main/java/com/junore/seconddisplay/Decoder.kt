package com.junore.seconddisplay

import android.media.MediaCodec
import android.media.MediaFormat
import android.view.Surface

class Decoder(private val surface: Surface, private val mime: String = "video/avc") {
    private val codec: MediaCodec = MediaCodec.createDecoderByType(mime)

    fun start(width: Int, height: Int) {
        val fmt = MediaFormat.createVideoFormat(mime, width, height)
        try { fmt.setInteger("low-latency", 1) } catch (_: Exception) {}
        try { fmt.setInteger(MediaFormat.KEY_LOW_LATENCY, 1) } catch (_: Exception) {}
        codec.configure(fmt, surface, null, 0)
        codec.start()
    }

    fun queue(sample: ByteArray, ptsUs: Long) {
        val inIndex = codec.dequeueInputBuffer(0)
        if (inIndex >= 0) {
            codec.getInputBuffer(inIndex)?.apply {
                clear(); put(sample)
            }
            codec.queueInputBuffer(inIndex, 0, sample.size, ptsUs, 0)
        }
        val info = MediaCodec.BufferInfo()
        var outIndex = codec.dequeueOutputBuffer(info, 0)
        while (outIndex >= 0) {
            codec.releaseOutputBuffer(outIndex, true)
            outIndex = codec.dequeueOutputBuffer(info, 0)
        }
    }

    fun stop() {
        try { codec.stop() } catch (_: Exception) {}
        try { codec.release() } catch (_: Exception) {}
    }
}
