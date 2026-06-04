const fs = require('fs');
const path = require('path');

console.log('--- KyokoBeat Android Native Customizer ---');

const manifestPath = path.join(__dirname, '../android/app/src/main/AndroidManifest.xml');
const mainActivityDir = path.join(__dirname, '../android/app/src/main/java/com/kyokobeat/musicplayer');
const mainActivityPath = path.join(mainActivityDir, 'MainActivity.java');
const xmlResDir = path.join(__dirname, '../android/app/src/main/res/xml');

// 1. Configure AndroidManifest.xml
if (fs.existsSync(manifestPath)) {
  let manifest = fs.readFileSync(manifestPath, 'utf8');

  const permissions = `
    <!-- KyokoBeat Storage & Media Audio Permissions -->
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />
    <uses-permission android:name="android.permission.READ_MEDIA_AUDIO" />
    <uses-permission android:name="android.permission.ACCESS_MEDIA_LOCATION" />
  `;

  if (!manifest.includes('READ_MEDIA_AUDIO')) {
    manifest = manifest.replace('<application', `${permissions}\n    <application`);
    console.log('✓ Injected storage & media permissions into AndroidManifest.xml');
  }

  if (!manifest.includes('android:requestLegacyExternalStorage')) {
    manifest = manifest.replace('<application', '<application android:requestLegacyExternalStorage="true"');
    console.log('✓ Added requestLegacyExternalStorage to application tag');
  }

  // ── FileProvider untuk WA Sticker ──
  const fileProvider = `
        <!-- WA Sticker FileProvider -->
        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="\${applicationId}.fileprovider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/file_paths" />
        </provider>`;

  if (!manifest.includes('FILE_PROVIDER_PATHS')) {
    manifest = manifest.replace('</application>', `${fileProvider}\n    </application>`);
    console.log('✓ Injected FileProvider for WA Sticker into AndroidManifest.xml');
  }

  fs.writeFileSync(manifestPath, manifest, 'utf8');
} else {
  console.error('Error: AndroidManifest.xml not found at:', manifestPath);
  process.exit(1);
}

// 2. Create file_paths.xml (diperlukan FileProvider)
fs.mkdirSync(xmlResDir, { recursive: true });
const filePathsXml = `<?xml version="1.0" encoding="utf-8"?>
<paths>
    <cache-path name="cache" path="." />
</paths>`;
const filePathsPath = path.join(xmlResDir, 'file_paths.xml');
if (!fs.existsSync(filePathsPath)) {
  fs.writeFileSync(filePathsPath, filePathsXml, 'utf8');
  console.log('✓ Created res/xml/file_paths.xml');
} else {
  // pastikan cache-path ada
  let existing = fs.readFileSync(filePathsPath, 'utf8');
  if (!existing.includes('cache-path')) {
    existing = existing.replace('</paths>', '    <cache-path name="cache" path="." />\n</paths>');
    fs.writeFileSync(filePathsPath, existing, 'utf8');
    console.log('✓ Updated file_paths.xml with cache-path');
  }
}

// 3. Write KyokoBeatNativePlugin.java
const pluginPath = path.join(mainActivityDir, 'KyokoBeatNativePlugin.java');
const pluginCode = `package com.kyokobeat.musicplayer;

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

@CapacitorPlugin(
    name = "KyokoBeatNative",
    permissions = {
        @Permission(
            strings = { Manifest.permission.READ_EXTERNAL_STORAGE },
            alias = "storage"
        ),
        @Permission(
            strings = { "android.permission.READ_MEDIA_AUDIO" },
            alias = "audio"
        )
    }
)
public class KyokoBeatNativePlugin extends Plugin {

    @PluginMethod
    public void checkAndRequestPermissions(PluginCall call) {
        if (Build.VERSION.SDK_INT >= 33) {
            if (getPermissionState("audio") != com.getcapacitor.PermissionState.GRANTED) {
                requestPermissionForAlias("audio", call, "permissionCallback");
                return;
            }
        } else {
            if (getPermissionState("storage") != com.getcapacitor.PermissionState.GRANTED) {
                requestPermissionForAlias("storage", call, "permissionCallback");
                return;
            }
        }
        JSObject ret = new JSObject();
        ret.put("granted", true);
        call.resolve(ret);
    }

    @PermissionCallback
    private void permissionCallback(PluginCall call) {
        JSObject ret = new JSObject();
        if (Build.VERSION.SDK_INT >= 33) {
            ret.put("granted", getPermissionState("audio") == com.getcapacitor.PermissionState.GRANTED);
        } else {
            ret.put("granted", getPermissionState("storage") == com.getcapacitor.PermissionState.GRANTED);
        }
        call.resolve(ret);
    }

    @PluginMethod
    public void querySongs(PluginCall call) {
        JSArray songs = new JSArray();
        ContentResolver contentResolver = getContext().getContentResolver();

        Uri uri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI;
        String selection = MediaStore.Audio.Media.DURATION + " > 0 AND " + MediaStore.Audio.Media.SIZE + " > 0";
        String sortOrder = MediaStore.Audio.Media.DATE_ADDED + " DESC";

        String[] projection = {
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.DATA,
            MediaStore.Audio.Media.SIZE,
            MediaStore.Audio.Media.ALBUM_ID
        };

        try (Cursor cursor = contentResolver.query(uri, projection, selection, null, sortOrder)) {
            if (cursor != null && cursor.moveToFirst()) {
                int idCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID);
                int titleCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE);
                int artistCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST);
                int albumCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM);
                int durationCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION);
                int dataCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA);
                int sizeCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE);
                int albumIdCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID);

                do {
                    long id = cursor.getLong(idCol);
                    String title = cursor.getString(titleCol);
                    String artist = cursor.getString(artistCol);
                    String album = cursor.getString(albumCol);
                    long durationMs = cursor.getLong(durationCol);
                    String filePath = cursor.getString(dataCol);
                    long size = cursor.getLong(sizeCol);
                    long albumId = cursor.getLong(albumIdCol);

                    Uri sArtworkUri = Uri.parse("content://media/external/audio/albumart");
                    Uri albumArtUri = ContentUris.withAppendedId(sArtworkUri, albumId);

                    JSObject song = new JSObject();
                    song.put("id", "mobile-" + id);
                    song.put("title", title != null ? title : "Unknown Title");
                    song.put("artist", artist == null || artist.equals("<unknown>") ? "Unknown Artist" : artist);
                    song.put("album", album == null || album.equals("<unknown>") ? "Unknown Album" : album);
                    song.put("duration", durationMs > 0 ? durationMs / 1000.0 : 180.0);
                    song.put("cover", albumArtUri.toString());
                    song.put("path", filePath);
                    song.put("fileSize", size);
                    song.put("addedAt", System.currentTimeMillis());
                    song.put("isCloud", false);
                    song.put("audioUrl", "https://localhost/_capacitor_file_" + filePath);

                    songs.put(song);
                } while (cursor.moveToNext());
            }

            JSObject result = new JSObject();
            result.put("songs", songs);
            call.resolve(result);
        } catch (Exception e) {
            call.reject("Failed to query MediaStore: " + e.getMessage(), e);
        }
    }
}
`;

fs.mkdirSync(mainActivityDir, { recursive: true });
fs.writeFileSync(pluginPath, pluginCode, 'utf8');
console.log('✓ Created KyokoBeatNativePlugin.java');

// 4. Write WAStickerPlugin.java  ← BARU
const waStickerPluginPath = path.join(mainActivityDir, 'WAStickerPlugin.java');
const waStickerPluginCode = `package com.kyokobeat.musicplayer;

import android.content.Intent;
import android.net.Uri;
import android.util.Base64;
import androidx.core.content.FileProvider;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import java.io.File;
import java.io.FileOutputStream;

/**
 * WAStickerPlugin
 * Buka WhatsApp "Add to your stickers" dialog langsung dari app.
 * Dipanggil dari StickerMakerPanel.tsx via WASticker.ts wrapper.
 */
@CapacitorPlugin(name = "WASticker")
public class WAStickerPlugin extends Plugin {

    @PluginMethod
    public void openPack(PluginCall call) {
        String base64Data = call.getString("data");
        String packName   = call.getString("packName", "sticker_pack");

        if (base64Data == null) {
            call.reject("No data provided");
            return;
        }

        try {
            // 1. Decode base64 -> bytes
            byte[] bytes = Base64.decode(base64Data, Base64.DEFAULT);

            // 2. Tulis ke cache dengan ekstensi .wastickers
            File file = new File(getContext().getCacheDir(), packName + ".wastickers");
            try (FileOutputStream fos = new FileOutputStream(file)) {
                fos.write(bytes);
            }

            // 3. URI aman via FileProvider
            Uri uri = FileProvider.getUriForFile(
                getContext(),
                getContext().getPackageName() + ".fileprovider",
                file
            );

            // 4. Intent VIEW -> WhatsApp tangkap & tampilkan "Add to your stickers"
            Intent intent = new Intent(Intent.ACTION_VIEW);
            intent.setDataAndType(uri, "application/octet-stream");
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);

            // Coba WhatsApp biasa dulu, lalu WA Business
            String[] waPackages = {"com.whatsapp", "com.whatsapp.w4b"};
            boolean launched = false;
            for (String pkg : waPackages) {
                try {
                    intent.setPackage(pkg);
                    getContext().startActivity(intent);
                    launched = true;
                    break;
                } catch (Exception ignored) {}
            }

            // Fallback: share chooser jika WA tidak terinstall
            if (!launched) {
                intent.setPackage(null);
                Intent chooser = Intent.createChooser(intent, "Buka dengan");
                chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                getContext().startActivity(chooser);
            }

            JSObject result = new JSObject();
            result.put("success", true);
            call.resolve(result);

        } catch (Exception e) {
            call.reject("Failed: " + e.getMessage());
        }
    }
}
`;
fs.writeFileSync(waStickerPluginPath, waStickerPluginCode, 'utf8');
console.log('✓ Created WAStickerPlugin.java');

// 5. Write MainActivity.java — daftarkan KEDUA plugin
const mainActivityCode = `package com.kyokobeat.musicplayer;

import android.os.Bundle;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        registerPlugin(KyokoBeatNativePlugin.class);
        registerPlugin(WAStickerPlugin.class);   // ← WA Sticker
        super.onCreate(savedInstanceState);
    }
}
`;
fs.writeFileSync(mainActivityPath, mainActivityCode, 'utf8');
console.log('✓ Updated MainActivity.java (KyokoBeatNative + WASticker)');

console.log('--- Customization Completed successfully ---');
