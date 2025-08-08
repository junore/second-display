package com.junore.seconddisplay

import android.view.MotionEvent

interface InputTransport {
    fun send(json: String)
}

class InputSender(private val transport: InputTransport) {
    fun onTouch(ev: MotionEvent, width: Int, height: Int) {
        val x = ev.x.toInt()
        val y = ev.y.toInt()
        transport.send("""{"type":"input","kind":"mouseMove","x":$x,"y":$y}""")
        when (ev.action) {
            MotionEvent.ACTION_DOWN -> transport.send("""{"type":"input","kind":"mouseDown","button":0}""")
            MotionEvent.ACTION_UP -> transport.send("""{"type":"input","kind":"mouseUp","button":0}""")
        }
    }
}
