package edu.coc.omr

import java.util.concurrent.ConcurrentHashMap

object ScannerCameraRegistry {
    private val sessions = ConcurrentHashMap<Int, ScannerCameraSession>()

    fun put(viewId: Int, session: ScannerCameraSession) {
        sessions[viewId] = session
    }

    fun get(viewId: Int): ScannerCameraSession? = sessions[viewId]

    fun remove(viewId: Int) {
        sessions.remove(viewId)?.release()
    }

    fun clear() {
        sessions.values.forEach { it.release() }
        sessions.clear()
    }
}
