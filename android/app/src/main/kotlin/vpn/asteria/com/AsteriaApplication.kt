package com.rsfly.vpn

import android.app.Application
import go.Seq
import org.amnezia.awg.backend.GoBackend

class RsFlyApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        GoBackend.vpnServiceClass = AsteriaAwgVpnService::class.java
        Seq.setContext(this)
    }
}
