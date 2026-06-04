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
    <uses-permission android:name="android.permission.READ_MEDIA_AUDIO" />
    <uses-permission android:name="android.permission.ACCESS_MEDIA_LOCATION" />`;
    manifest = manifest.replace('<application', `${perms}\n    <application`);
    console.log('✓ Injected storage permissions');
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
// 5. WAStickerPlugin.java  ← Pakai ENABLE_STICKER_PACK intent
// ─────────────────────────────────────────────────────────
const waStickerCode = `package com.kyokobeat.musicplayer;

import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.util.Base64;
import android.util.Log;

import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;

/**
 * WAStickerPlugin
 * Simpan stiker ke cache → fire ENABLE_STICKER_PACK intent.
 * WhatsApp buka sheet "Tambahkan ke stiker Anda" secara otomatis.
 */
@CapacitorPlugin(name = "WASticker")
public class WAStickerPlugin extends Plugin {

    private static final String TAG = "WAStickerPlugin";

    @PluginMethod
    public void openPack(PluginCall call) {
        String packId     = call.getString("packId",    "kyoko_" + System.currentTimeMillis());
        String packName   = call.getString("packName",  "Sticker Pack");
        String publisher  = call.getString("publisher", "KyokoBeat");
        String trayData   = call.getString("trayData");   // base64 WebP 96x96
        JSArray stickers  = call.getArray("stickers");    // [{fileName, data, emoji}]

        if (trayData == null || stickers == null) {
            call.reject("Missing trayData or stickers"); return;
        }

        try {
            // Simpan ke cache/wa_stickers/{packId}/
            File packDir = new File(getContext().getCacheDir(), "wa_stickers/" + packId);
            packDir.mkdirs();

            // tray image (96x96)
            writeFile(new File(packDir, "tray.webp"), Base64.decode(trayData, Base64.DEFAULT));

            // setiap stiker
            for (int i = 0; i < stickers.length(); i++) {
                JSONObject s = stickers.getJSONObject(i);
                String fileName = s.getString("fileName");
                String data     = s.getString("data");
                writeFile(new File(packDir, fileName), Base64.decode(data, Base64.DEFAULT));
            }

            // metadata untuk ContentProvider
            JSONObject meta = new JSONObject();
            meta.put("name", packName);
            meta.put("publisher", publisher);
            writeFile(new File(packDir, "meta.json"), meta.toString().getBytes());

            // Fire ENABLE_STICKER_PACK — WA tampilkan sheet "Tambahkan ke stiker Anda"
            Intent intent = new Intent("com.whatsapp.intent.action.ENABLE_STICKER_PACK");
            intent.putExtra("sticker_pack_id",        packId);
            intent.putExtra("sticker_pack_name",      packName);
            intent.putExtra("sticker_pack_publisher", publisher);
            intent.putExtra("sticker_pack_localized_name", packName);
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);

            boolean launched = false;
            for (String pkg : new String[]{"com.whatsapp", "com.whatsapp.w4b"}) {
                try {
                    intent.setPackage(pkg);
                    getActivity().startActivityForResult(intent, 200);
                    launched = true;
                    Log.d(TAG, "Opened WA: " + pkg);
                    break;
                } catch (ActivityNotFoundException ignored) {}
            }

            if (!launched) {
                call.reject("WhatsApp tidak terinstall"); return;
            }

            JSObject result = new JSObject();
            result.put("success", true);
            call.resolve(result);

        } catch (Exception e) {
            Log.e(TAG, "Error: " + e.getMessage(), e);
            call.reject("Failed: " + e.getMessage());
        }
    }

    private void writeFile(File file, byte[] data) throws Exception {
        try (FileOutputStream fos = new FileOutputStream(file)) { fos.write(data); }
    }
}
`;
const waPath = path.join(mainActivityDir, 'WAStickerPlugin.java');
fs.writeFileSync(waPath, waStickerCode, 'utf8');
console.log('✓ Created WAStickerPlugin.java');

// ─────────────────────────────────────────────────────────
// 6. MainActivity.java — daftarkan semua plugin
// ─────────────────────────────────────────────────────────
const mainActivityCode = `package com.kyokobeat.musicplayer;

import android.os.Bundle;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        registerPlugin(KyokoBeatNativePlugin.class);
        registerPlugin(WAStickerPlugin.class);
        super.onCreate(savedInstanceState);
    }
}
`;
fs.writeFileSync(mainActivityPath, mainActivityCode, 'utf8');
console.log('✓ Updated MainActivity.java');

console.log('--- Done! Semua native code siap ---');
