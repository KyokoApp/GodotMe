const fs = require('fs');
const path = require('path');

console.log('--- KyokoBeat Android Native Customizer ---');

const manifestPath    = path.join(__dirname, '../android/app/src/main/AndroidManifest.xml');
const mainActivityDir = path.join(__dirname, '../android/app/src/main/java/com/kyokobeat/musicplayer');
const mainActivityPath = path.join(mainActivityDir, 'MainActivity.java');
const xmlResDir       = path.join(__dirname, '../android/app/src/main/res/xml');

// ─────────────────────────────────────────────────────────
// 1. AndroidManifest.xml
// ─────────────────────────────────────────────────────────
if (fs.existsSync(manifestPath)) {
  let manifest = fs.readFileSync(manifestPath, 'utf8');

  // Storage permissions
  if (!manifest.includes('READ_MEDIA_AUDIO')) {
    const perms = `
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28" />
    <uses-permission android:name="android.permission.READ_MEDIA_AUDIO" />
    <uses-permission android:name="android.permission.ACCESS_MEDIA_LOCATION" />`;
    manifest = manifest.replace('<application', `${perms}\n    <application`);
    console.log('✓ Injected storage permissions');
  }

  // Floating overlay permission
  if (!manifest.includes('SYSTEM_ALERT_WINDOW')) {
    manifest = manifest.replace('<application', `<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW" />\n    <application`);
    console.log('✓ Added SYSTEM_ALERT_WINDOW permission');
  }

  if (!manifest.includes('android:requestLegacyExternalStorage')) {
    manifest = manifest.replace('<application', '<application android:requestLegacyExternalStorage="true"');
    console.log('✓ Added requestLegacyExternalStorage');
  }

  // StickerContentProvider — wajib untuk WhatsApp Sticker API
  if (!manifest.includes('stickercontentprovider')) {
    const provider = `
        <!-- WhatsApp Sticker ContentProvider -->
        <provider
            android:name=".StickerContentProvider"
            android:authorities="com.kyokobeat.musicplayer.stickercontentprovider"
            android:exported="true"
            android:readPermission="com.whatsapp.permission.STICKER_PROVIDER_READ" />`;
    manifest = manifest.replace('</application>', `${provider}\n    </application>`);
    console.log('✓ Registered StickerContentProvider');
  }

  // WhatsApp sticker read permission
  if (!manifest.includes('STICKER_PROVIDER_READ')) {
    manifest = manifest.replace(
      '<manifest',
      '<manifest\n    xmlns:tools="http://schemas.android.com/tools"'
        .replace('<manifest\n    xmlns:tools', manifest.includes('xmlns:tools') ? '' : '<manifest\n    xmlns:tools')
    );
    // simpler: just add uses-permission
    if (!manifest.includes('com.whatsapp.permission.STICKER_PROVIDER_READ')) {
      manifest = manifest.replace(
        '<application',
        `<uses-permission android:name="com.whatsapp.permission.STICKER_PROVIDER_READ" />\n    <application`
      );
    }
    console.log('✓ Added WhatsApp sticker permission');
  }

  fs.writeFileSync(manifestPath, manifest, 'utf8');
} else {
  console.error('AndroidManifest.xml not found'); process.exit(1);
}

// ─────────────────────────────────────────────────────────
// 2. file_paths.xml
// ─────────────────────────────────────────────────────────
fs.mkdirSync(xmlResDir, { recursive: true });
const filePathsPath = path.join(xmlResDir, 'file_paths.xml');
if (!fs.existsSync(filePathsPath)) {
  fs.writeFileSync(filePathsPath, `<?xml version="1.0" encoding="utf-8"?>\n<paths>\n    <cache-path name="cache" path="." />\n</paths>`, 'utf8');
  console.log('✓ Created file_paths.xml');
}

// ─────────────────────────────────────────────────────────
// 3. KyokoBeatNativePlugin.java (tidak berubah)
// ─────────────────────────────────────────────────────────
fs.mkdirSync(mainActivityDir, { recursive: true });
const nativePluginPath = path.join(mainActivityDir, 'KyokoBeatNativePlugin.java');
const nativePluginCode = `package com.kyokobeat.musicplayer;

import android.Manifest;
import android.content.ContentResolver;
import android.content.ContentUris;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.provider.MediaStore;
import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.getcapacitor.annotation.Permission;
import com.getcapacitor.annotation.PermissionCallback;

@CapacitorPlugin(name = "KyokoBeatNative", permissions = {
    @Permission(strings = { Manifest.permission.READ_EXTERNAL_STORAGE }, alias = "storage"),
    @Permission(strings = { "android.permission.READ_MEDIA_AUDIO" }, alias = "audio")
})
public class KyokoBeatNativePlugin extends Plugin {

    @PluginMethod
    public void checkAndRequestPermissions(PluginCall call) {
        if (Build.VERSION.SDK_INT >= 33) {
            if (getPermissionState("audio") != com.getcapacitor.PermissionState.GRANTED) {
                requestPermissionForAlias("audio", call, "permissionCallback"); return;
            }
        } else {
            if (getPermissionState("storage") != com.getcapacitor.PermissionState.GRANTED) {
                requestPermissionForAlias("storage", call, "permissionCallback"); return;
            }
        }
        JSObject ret = new JSObject(); ret.put("granted", true); call.resolve(ret);
    }

    @PermissionCallback
    private void permissionCallback(PluginCall call) {
        JSObject ret = new JSObject();
        ret.put("granted", Build.VERSION.SDK_INT >= 33
            ? getPermissionState("audio") == com.getcapacitor.PermissionState.GRANTED
            : getPermissionState("storage") == com.getcapacitor.PermissionState.GRANTED);
        call.resolve(ret);
    }

    @PluginMethod
    public void querySongs(PluginCall call) {
        JSArray songs = new JSArray();
        ContentResolver cr = getContext().getContentResolver();
        Uri uri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI;
        String[] projection = {
            MediaStore.Audio.Media._ID, MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST, MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION, MediaStore.Audio.Media.DATA,
            MediaStore.Audio.Media.SIZE, MediaStore.Audio.Media.ALBUM_ID
        };
        try (Cursor c = cr.query(uri, projection,
                MediaStore.Audio.Media.DURATION + " > 0 AND " + MediaStore.Audio.Media.SIZE + " > 0",
                null, MediaStore.Audio.Media.DATE_ADDED + " DESC")) {
            if (c != null && c.moveToFirst()) {
                do {
                    long id = c.getLong(c.getColumnIndexOrThrow(MediaStore.Audio.Media._ID));
                    long albumId = c.getLong(c.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID));
                    Uri artUri = ContentUris.withAppendedId(Uri.parse("content://media/external/audio/albumart"), albumId);
                    JSObject song = new JSObject();
                    song.put("id", "mobile-" + id);
                    song.put("title", c.getString(c.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)));
                    String artist = c.getString(c.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST));
                    song.put("artist", artist == null || artist.equals("<unknown>") ? "Unknown Artist" : artist);
                    String album = c.getString(c.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM));
                    song.put("album", album == null || album.equals("<unknown>") ? "Unknown Album" : album);
                    long dur = c.getLong(c.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION));
                    song.put("duration", dur > 0 ? dur / 1000.0 : 180.0);
                    song.put("cover", artUri.toString());
                    String fp = c.getString(c.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA));
                    song.put("path", fp);
                    song.put("fileSize", c.getLong(c.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE)));
                    song.put("addedAt", System.currentTimeMillis());
                    song.put("isCloud", false);
                    song.put("audioUrl", "https://localhost/_capacitor_file_" + fp);
                    songs.put(song);
                } while (c.moveToNext());
            }
        } catch (Exception e) { call.reject("Failed: " + e.getMessage(), e); return; }
        JSObject result = new JSObject(); result.put("songs", songs); call.resolve(result);
    }
}
`;
fs.writeFileSync(nativePluginPath, nativePluginCode, 'utf8');
console.log('✓ Created KyokoBeatNativePlugin.java');

// ─────────────────────────────────────────────────────────
// 4. StickerContentProvider.java  ← BARU (kunci WA Sticker API)
// ─────────────────────────────────────────────────────────
const contentProviderCode = `package com.kyokobeat.musicplayer;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.UriMatcher;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.util.Log;

import org.json.JSONObject;

import java.io.File;
import java.io.FileNotFoundException;
import java.nio.file.Files;

/**
 * StickerContentProvider
 * Menyajikan data stiker ke WhatsApp melalui WhatsApp Sticker API resmi.
 * WhatsApp query provider ini setelah menerima ENABLE_STICKER_PACK intent.
 */
public class StickerContentProvider extends ContentProvider {

    static final String AUTHORITY = "com.kyokobeat.musicplayer.stickercontentprovider";
    private static final UriMatcher MATCHER = new UriMatcher(UriMatcher.NO_MATCH);
    private static final int METADATA_ALL   = 1;
    private static final int METADATA_SINGLE = 2;
    private static final int STICKERS_LIST  = 3;
    private static final int STICKER_FILE   = 4;

    static {
        MATCHER.addURI(AUTHORITY, "metadata",    METADATA_ALL);
        MATCHER.addURI(AUTHORITY, "metadata/*",  METADATA_SINGLE);
        MATCHER.addURI(AUTHORITY, "stickers/*",  STICKERS_LIST);
        MATCHER.addURI(AUTHORITY, "stickers/*/*", STICKER_FILE);
    }

    @Override public boolean onCreate() { return true; }

    @Override
    public Cursor query(Uri uri, String[] proj, String sel, String[] selArgs, String sort) {
        int code = MATCHER.match(uri);
        if (code == METADATA_ALL || code == METADATA_SINGLE) return getMetadata(uri, code);
        if (code == STICKERS_LIST) return getStickerList(uri);
        throw new IllegalArgumentException("Unknown URI: " + uri);
    }

    private Cursor getMetadata(Uri uri, int code) {
        String[] cols = {
            "sticker_pack_identifier", "sticker_pack_name", "sticker_pack_publisher",
            "sticker_pack_icon_image_file", "android_play_store_link", "ios_app_store_link",
            "image_data_version", "avoid_cache"
        };
        MatrixCursor cursor = new MatrixCursor(cols);
        File root = new File(getContext().getCacheDir(), "wa_stickers");
        if (!root.exists()) return cursor;
        File[] packs = root.listFiles(File::isDirectory);
        if (packs == null) return cursor;
        for (File pack : packs) {
            if (code == METADATA_SINGLE && !pack.getName().equals(uri.getLastPathSegment())) continue;
            File metaFile = new File(pack, "meta.json");
            if (!metaFile.exists()) continue;
            try {
                String raw = new String(Files.readAllBytes(metaFile.toPath()));
                JSONObject meta = new JSONObject(raw);
                cursor.addRow(new Object[]{
                    pack.getName(),
                    meta.optString("name", "Sticker Pack"),
                    meta.optString("publisher", "KyokoBeat"),
                    "tray.webp", "", "", "1", "false"
                });
            } catch (Exception e) { Log.e("StickerCP", e.getMessage()); }
        }
        return cursor;
    }

    private Cursor getStickerList(Uri uri) {
        MatrixCursor cursor = new MatrixCursor(new String[]{"sticker_file_name", "sticker_emoji"});
        File packDir = new File(getContext().getCacheDir(), "wa_stickers/" + uri.getLastPathSegment());
        if (!packDir.exists()) return cursor;
        File[] files = packDir.listFiles(f -> f.getName().endsWith(".webp") && !f.getName().equals("tray.webp"));
        if (files != null) for (File f : files) cursor.addRow(new Object[]{f.getName(), "\\uD83D\\uDE0A"});
        return cursor;
    }

    @Override
    public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
        if (MATCHER.match(uri) == STICKER_FILE) {
            String packId = uri.getPathSegments().get(1);
            String fileName = uri.getPathSegments().get(2);
            File file = new File(getContext().getCacheDir(), "wa_stickers/" + packId + "/" + fileName);
            if (file.exists()) return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY);
        }
        throw new FileNotFoundException("Not found: " + uri);
    }

    @Override public String getType(Uri uri) { return "image/webp"; }
    @Override public Uri insert(Uri u, ContentValues v) { return null; }
    @Override public int delete(Uri u, String s, String[] a) { return 0; }
    @Override public int update(Uri u, ContentValues v, String s, String[] a) { return 0; }
}
`;
const cpPath = path.join(mainActivityDir, 'StickerContentProvider.java');
fs.writeFileSync(cpPath, contentProviderCode, 'utf8');
console.log('✓ Created StickerContentProvider.java');

// ─────────────────────────────────────────────────────────
// 5. WAStickerPlugin.java
//    Android 10+: tulis ke Downloads via MediaStore → URI dikenali WA
//    Android 9- : FileProvider fallback
// ─────────────────────────────────────────────────────────
const waStickerCode = `package com.kyokobeat.musicplayer;

import android.content.ContentValues;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.provider.MediaStore;
import android.util.Base64;
import androidx.core.content.FileProvider;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStream;

/**
 * WAStickerPlugin
 * Tulis .wastickers ke Downloads (MediaStore) agar WA muncul
 * di "Buka Dengan" dan menampilkan "Tambahkan ke stiker Anda".
 */
@CapacitorPlugin(name = "WASticker")
public class WAStickerPlugin extends Plugin {

    @PluginMethod
    public void openPack(PluginCall call) {
        String base64Data = call.getString("data");
        String packName   = call.getString("packName", "sticker_pack")
                              .replaceAll("[^a-zA-Z0-9_\\\\-]", "_");

        if (base64Data == null) { call.reject("No data"); return; }

        try {
            byte[] bytes = Base64.decode(base64Data, Base64.DEFAULT);
            Uri fileUri;

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // Android 10+ — tulis ke Downloads via MediaStore
                // URI yang dihasilkan = content://media/external/downloads/...
                // WA register sebagai handler untuk URI jenis ini ✓
                ContentValues values = new ContentValues();
                values.put(MediaStore.Downloads.DISPLAY_NAME, packName + ".wastickers");
                values.put(MediaStore.Downloads.MIME_TYPE, "application/octet-stream");
                values.put(MediaStore.Downloads.IS_PENDING, 1);

                Uri col = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY);
                fileUri = getContext().getContentResolver().insert(col, values);
                if (fileUri == null) throw new Exception("MediaStore insert gagal");

                try (OutputStream os = getContext().getContentResolver().openOutputStream(fileUri)) {
                    if (os == null) throw new Exception("Cannot open stream");
                    os.write(bytes);
                }

                values.clear();
                values.put(MediaStore.Downloads.IS_PENDING, 0);
                getContext().getContentResolver().update(fileUri, values, null, null);

            } else {
                // Android 9 ke bawah — FileProvider fallback
                File file = new File(getContext().getCacheDir(), packName + ".wastickers");
                try (FileOutputStream fos = new FileOutputStream(file)) { fos.write(bytes); }
                fileUri = FileProvider.getUriForFile(
                    getContext(),
                    getContext().getPackageName() + ".fileprovider",
                    file
                );
            }

            Intent intent = new Intent(Intent.ACTION_VIEW);
            intent.setData(fileUri);
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            getContext().startActivity(intent);

            JSObject result = new JSObject();
            result.put("success", true);
            call.resolve(result);

        } catch (Exception e) {
            call.reject("Failed: " + e.getMessage());
        }
    }
}
`;
const waPath = path.join(mainActivityDir, 'WAStickerPlugin.java');
fs.writeFileSync(waPath, waStickerCode, 'utf8');
console.log('✓ Created WAStickerPlugin.java');

// ─────────────────────────────────────────────────────────
// 6. FloatingLyricsPlugin.java
// ─────────────────────────────────────────────────────────
const floatingLyricsCode = `package com.kyokobeat.musicplayer;

import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import android.util.DisplayMetrics;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;
import android.view.animation.AlphaAnimation;
import android.view.animation.Animation;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

@CapacitorPlugin(name = "FloatingLyrics")
public class FloatingLyricsPlugin extends Plugin {

    private WindowManager windowManager;
    private FrameLayout rootView;
    private LinearLayout card;
    private TextView lyricsText;
    private WindowManager.LayoutParams params;
    private boolean isShowing = false;
    private String lastLine = "";

    @PluginMethod
    public void requestPermission(PluginCall call) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!Settings.canDrawOverlays(getContext())) {
                Intent intent = new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:" + getContext().getPackageName()));
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                getContext().startActivity(intent);
                JSObject r = new JSObject();
                r.put("granted", false);
                r.put("prompted", true);
                call.resolve(r);
                return;
            }
        }
        JSObject r = new JSObject(); r.put("granted", true); call.resolve(r);
    }

    @PluginMethod
    public void checkPermission(PluginCall call) {
        boolean granted = Build.VERSION.SDK_INT < Build.VERSION_CODES.M
            || Settings.canDrawOverlays(getContext());
        JSObject r = new JSObject(); r.put("granted", granted); call.resolve(r);
    }

    @PluginMethod
    public void showLyrics(PluginCall call) {
        String line = call.getString("line", "");
        getActivity().runOnUiThread(() -> {
            if (!isShowing) {
                createFloatingView(line);
            } else if (!line.equals(lastLine)) {
                updateLyricWithFade(line);
            }
            lastLine = line;
            JSObject r = new JSObject(); r.put("ok", true); call.resolve(r);
        });
    }

    @PluginMethod
    public void hideLyrics(PluginCall call) {
        getActivity().runOnUiThread(() -> {
            destroyFloatingView();
            JSObject r = new JSObject(); r.put("ok", true); call.resolve(r);
        });
    }

    @PluginMethod
    public void isVisible(PluginCall call) {
        JSObject r = new JSObject(); r.put("visible", isShowing); call.resolve(r);
    }

    private void updateLyricWithFade(String newLine) {
        if (lyricsText == null) return;
        AlphaAnimation fadeOut = new AlphaAnimation(1f, 0.2f);
        fadeOut.setDuration(150);
        fadeOut.setAnimationListener(new Animation.AnimationListener() {
            public void onAnimationStart(Animation a) {}
            public void onAnimationRepeat(Animation a) {}
            public void onAnimationEnd(Animation a) {
                lyricsText.setText(newLine);
                AlphaAnimation fadeIn = new AlphaAnimation(0.2f, 1f);
                fadeIn.setDuration(200);
                lyricsText.startAnimation(fadeIn);
            }
        });
        lyricsText.startAnimation(fadeOut);
    }

    private void createFloatingView(String initialText) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(getContext())) return;

        windowManager = (WindowManager) getContext().getSystemService(Context.WINDOW_SERVICE);
        DisplayMetrics dm = getContext().getResources().getDisplayMetrics();
        int screenW = dm.widthPixels;
        int cardW = (int)(screenW * 0.88f);
        int dp = (int) dm.density;

        // Root transparent hit area
        rootView = new FrameLayout(getContext());

        // Card with rounded background
        card = new LinearLayout(getContext());
        card.setOrientation(LinearLayout.VERTICAL);
        card.setGravity(Gravity.CENTER);
        card.setPadding(20 * dp, 14 * dp, 20 * dp, 14 * dp);

        GradientDrawable bg = new GradientDrawable();
        bg.setShape(GradientDrawable.RECTANGLE);
        bg.setCornerRadius(20 * dp);
        bg.setColor(Color.parseColor("#E60d0d0d"));
        bg.setStroke(1, Color.parseColor("#33c8f500"));
        card.setBackground(bg);

        // Drag handle dots at top
        TextView handle = new TextView(getContext());
        handle.setText("• • •");
        handle.setTextColor(Color.parseColor("#44c8f500"));
        handle.setTextSize(8f);
        handle.setGravity(Gravity.CENTER);
        handle.setPadding(0, 0, 0, 6 * dp);
        card.addView(handle);

        // Lyrics text
        lyricsText = new TextView(getContext());
        lyricsText.setText(initialText);
        lyricsText.setTextColor(Color.parseColor("#c8f500"));
        lyricsText.setTextSize(15f);
        lyricsText.setTypeface(Typeface.DEFAULT_BOLD);
        lyricsText.setGravity(Gravity.CENTER);
        lyricsText.setMaxLines(2);
        lyricsText.setEllipsize(android.text.TextUtils.TruncateAt.END);
        lyricsText.setLineSpacing(4 * dp, 1f);
        card.addView(lyricsText, new LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ));

        // Close button row
        TextView closeBtn = new TextView(getContext());
        closeBtn.setText("✕  tutup");
        closeBtn.setTextColor(Color.parseColor("#55ffffff"));
        closeBtn.setTextSize(9f);
        closeBtn.setGravity(Gravity.CENTER);
        closeBtn.setPadding(0, 8 * dp, 0, 0);
        closeBtn.setOnClickListener(v -> destroyFloatingView());
        card.addView(closeBtn);

        FrameLayout.LayoutParams cardParams = new FrameLayout.LayoutParams(cardW, FrameLayout.LayoutParams.WRAP_CONTENT);
        cardParams.gravity = Gravity.CENTER;
        rootView.addView(card, cardParams);

        // Fade in on appear
        AlphaAnimation fadeIn = new AlphaAnimation(0f, 1f);
        fadeIn.setDuration(300);
        rootView.startAnimation(fadeIn);

        // Window layout
        int type = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
            ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            : WindowManager.LayoutParams.TYPE_PHONE;

        params = new WindowManager.LayoutParams(
            screenW,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        );
        params.gravity = Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL;
        params.x = 0;
        params.y = 160 * dp;

        // Drag support on card
        card.setOnTouchListener(new View.OnTouchListener() {
            float initY, touchY;
            boolean dragging = false;
            @Override
            public boolean onTouch(View v, MotionEvent e) {
                switch (e.getAction()) {
                    case MotionEvent.ACTION_DOWN:
                        initY = params.y; touchY = e.getRawY(); dragging = false;
                        return true;
                    case MotionEvent.ACTION_MOVE:
                        float dy = e.getRawY() - touchY;
                        if (Math.abs(dy) > 8) dragging = true;
                        if (dragging) {
                            params.y = (int)(initY - dy);
                            windowManager.updateViewLayout(rootView, params);
                        }
                        return true;
                    case MotionEvent.ACTION_UP:
                        return dragging;
                }
                return false;
            }
        });

        windowManager.addView(rootView, params);
        isShowing = true;
    }

    private void destroyFloatingView() {
        if (rootView != null && windowManager != null) {
            AlphaAnimation fadeOut = new AlphaAnimation(1f, 0f);
            fadeOut.setDuration(200);
            fadeOut.setAnimationListener(new Animation.AnimationListener() {
                public void onAnimationStart(Animation a) {}
                public void onAnimationRepeat(Animation a) {}
                public void onAnimationEnd(Animation a) {
                    try { windowManager.removeView(rootView); } catch (Exception ignored) {}
                }
            });
            rootView.startAnimation(fadeOut);
            rootView = null; lyricsText = null; isShowing = false;
        }
    }

    @Override
    protected void handleOnDestroy() {
        destroyFloatingView();
        super.handleOnDestroy();
    }
}
`;
const flPath = path.join(mainActivityDir, 'FloatingLyricsPlugin.java');
fs.writeFileSync(flPath, floatingLyricsCode, 'utf8');
console.log('✓ Created FloatingLyricsPlugin.java');

// ─────────────────────────────────────────────────────────
// 8. Inject FOREGROUND_SERVICE permission + media support lib in build.gradle
// ─────────────────────────────────────────────────────────
if (fs.existsSync(manifestPath)) {
  let manifest = fs.readFileSync(manifestPath, 'utf8');
  if (!manifest.includes('FOREGROUND_SERVICE')) {
    manifest = manifest.replace(
      '<application',
      `<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />\n    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />\n    <uses-permission android:name="android.permission.WAKE_LOCK" />\n    <application`
    );
    console.log('✓ Added FOREGROUND_SERVICE + WAKE_LOCK permissions');
  }

  // jofr plugin declares MediaSessionService automatically — no manual declaration needed

  fs.writeFileSync(manifestPath, manifest, 'utf8');
}

// Tambah androidx.media dependency ke build.gradle kalau belum ada
const appBuildGradlePath = path.join(__dirname, '../android/app/build.gradle');
if (fs.existsSync(appBuildGradlePath)) {
  let gradle = fs.readFileSync(appBuildGradlePath, 'utf8');
  if (!gradle.includes('androidx.media:media')) {
    gradle = gradle.replace(
      /dependencies\s*\{/,
      `dependencies {\n    implementation 'androidx.media:media:1.7.1'`
    );
    fs.writeFileSync(appBuildGradlePath, gradle, 'utf8');
    console.log('✓ Added androidx.media dependency to build.gradle');
  }
}

// ─────────────────────────────────────────────────────────
// 9. MainActivity.java — daftarkan semua plugin
// ─────────────────────────────────────────────────────────
const mainActivityCode = `package com.kyokobeat.musicplayer;

import android.os.Bundle;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        registerPlugin(KyokoBeatNativePlugin.class);
        registerPlugin(WAStickerPlugin.class);
        registerPlugin(FloatingLyricsPlugin.class);
        super.onCreate(savedInstanceState);
    }

    /**
     * Capacitor BridgeActivity.onPause() memanggil webView.onPause() yang
     * men-suspend JavaScript & mematikan audio WebView di background.
     * Kita re-resume WebView setelah super selesai agar audio tetap jalan.
     */
    @Override
    public void onPause() {
        super.onPause();
        if (getBridge() != null && getBridge().getWebView() != null) {
            getBridge().getWebView().onResume();
        }
    }

    /**
     * onStop() juga memanggil bridge.onStop() yang bisa suppress WebView lebih lanjut.
     */
    @Override
    public void onStop() {
        super.onStop();
        if (getBridge() != null && getBridge().getWebView() != null) {
            getBridge().getWebView().onResume();
        }
    }
}
`;
fs.writeFileSync(mainActivityPath, mainActivityCode, 'utf8');
console.log('✓ Updated MainActivity.java');

console.log('--- Done! Semua native code siap ---');
