package edu.coc.omr

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.lifecycle.LifecycleOwner

fun Context.findActivity(): Activity? {
    var current: Context = this
    while (current is ContextWrapper) {
        if (current is Activity) {
            return current
        }
        current = current.baseContext
    }
    return null
}

fun Context.findLifecycleOwner(): LifecycleOwner? {
    val activity = findActivity()
    return activity as? LifecycleOwner
}
