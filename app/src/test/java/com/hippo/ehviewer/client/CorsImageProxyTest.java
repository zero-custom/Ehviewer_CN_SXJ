package com.hippo.ehviewer.client;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

import org.junit.Test;

public class CorsImageProxyTest {

    @Test
    public void normalizeServerAcceptsHttpAndHttps() {
        assertEquals("https://cors.example.com/",
                CorsImageProxy.normalizeServer(" https://cors.example.com/// "));
        assertEquals("http://cors.example.com/",
                CorsImageProxy.normalizeServer("http://cors.example.com"));
    }

    @Test
    public void normalizeServerRejectsInvalidInputs() {
        assertNull(CorsImageProxy.normalizeServer(null));
        assertNull(CorsImageProxy.normalizeServer("   "));
        assertNull(CorsImageProxy.normalizeServer("cors.example.com"));
        assertNull(CorsImageProxy.normalizeServer("ftp://cors.example.com"));
        assertNull(CorsImageProxy.normalizeServer("https://"));
        assertNull(CorsImageProxy.normalizeServer("http:///"));
        assertNull(CorsImageProxy.normalizeServer("https:///path"));
    }

    @Test
    public void proxyUrlPrefixesOriginalUrl() {
        assertEquals("https://cors.example.com/https://img.example.com/a.webp",
                CorsImageProxy.proxyUrl("https://cors.example.com/",
                        "https://img.example.com/a.webp"));
    }

    @Test
    public void proxyUrlIsIdempotent() {
        String url = "https://cors.example.com/https://img.example.com/a.webp";
        assertEquals(url, CorsImageProxy.proxyUrl("https://cors.example.com", url));
    }

    @Test
    public void proxyUrlRejectsInvalidInputs() {
        assertNull(CorsImageProxy.proxyUrl("", "https://img.example.com/a.webp"));
        assertNull(CorsImageProxy.proxyUrl("https://cors.example.com/", null));
        assertNull(CorsImageProxy.proxyUrl("https://cors.example.com/", "file:///a.webp"));
    }
}
