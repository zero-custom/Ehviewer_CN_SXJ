package com.hippo.ehviewer.client;

import androidx.annotation.Nullable;

import com.hippo.ehviewer.Settings;

import java.net.URI;
import java.net.URISyntaxException;
import java.util.Locale;

/**
 * Builds path-prefix CORS relay URLs: {@code server + originalUrl}.
 *
 * <p>The relay is only used when the user enables it and the configured server
 * is a valid http(s) prefix. The helper is deliberately free of OkHttp/Android
 * UI dependencies so it can be unit-tested.</p>
 */
public final class CorsImageProxy {

    private CorsImageProxy() {
    }

    /**
     * Normalizes a user-supplied relay prefix to exactly one trailing slash.
     * Returns {@code null} when the value is empty or is not an http(s) URL.
     */
    @Nullable
    public static String normalizeServer(@Nullable String raw) {
        if (raw == null) {
            return null;
        }
        String value = raw.trim();
        if (value.isEmpty()) {
            return null;
        }
        String lower = value.toLowerCase(Locale.ROOT);
        if (!lower.startsWith("http://") && !lower.startsWith("https://")) {
            return null;
        }
        // Reject scheme-only values such as "https://" and malformed prefixes;
        // an invalid server must behave like the feature being disabled.
        try {
            URI uri = new URI(value);
            String scheme = uri.getScheme();
            String host = uri.getHost();
            if (scheme == null || host == null || host.isEmpty()) {
                return null;
            }
            if (!"http".equalsIgnoreCase(scheme) && !"https".equalsIgnoreCase(scheme)) {
                return null;
            }
        } catch (URISyntaxException e) {
            return null;
        }
        while (value.endsWith("/")) {
            value = value.substring(0, value.length() - 1);
        }
        if (value.isEmpty()) {
            return null;
        }
        return value + "/";
    }

    public static boolean isEnabled() {
        return Settings.getCorsImageEnabled()
                && normalizeServer(Settings.getCorsImageServer()) != null;
    }

    /**
     * Returns the relay URL for an image, or {@code null} when the feature is
     * disabled or the URL is not an eligible http(s) URL.
     */
    @Nullable
    public static String proxyUrl(@Nullable String originalUrl) {
        if (!Settings.getCorsImageEnabled()) {
            return null;
        }
        return proxyUrl(Settings.getCorsImageServer(), originalUrl);
    }

    /**
     * Pure overload used by callers and unit tests.
     */
    @Nullable
    public static String proxyUrl(@Nullable String server, @Nullable String originalUrl) {
        String prefix = normalizeServer(server);
        if (prefix == null || originalUrl == null) {
            return null;
        }
        String url = originalUrl.trim();
        if (url.isEmpty()) {
            return null;
        }
        if (!url.startsWith("http://") && !url.startsWith("https://")) {
            return null;
        }
        // Keep the operation idempotent when a URL is already relayed.
        if (url.startsWith(prefix)) {
            return url;
        }
        return prefix + url;
    }

    public static boolean isProxied(@Nullable String requestUrl) {
        if (!Settings.getCorsImageEnabled()) {
            return false;
        }
        String prefix = normalizeServer(Settings.getCorsImageServer());
        return prefix != null && requestUrl != null && requestUrl.startsWith(prefix);
    }
}
