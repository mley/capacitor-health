package com.fit_up.health.capacitor

import android.annotation.SuppressLint
import android.app.Activity
import android.os.Bundle
import android.webkit.WebView

class PermissionsRationaleActivity : Activity() {

    @SuppressLint("DiscouragedApi")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val webView = WebView(applicationContext)
        setContentView(webView)

        val url = getString(resources.getIdentifier("privacy_policy_url", "string", packageName))
        webView.loadUrl(url)
    }
}