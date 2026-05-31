const fs = require('fs');
const path = require('path');

console.log('--- KyokoBeat Android Native Customizer ---');

const manifestPath = path.join(__dirname, '../android/app/src/main/AndroidManifest.xml');
const mainActivityDir = path.join(__dirname, '../android/app/src/main/java/com/kyokobeat/musicplayer');
const mainActivityPath = path.join(mainActivityDir, 'MainActivity.java');

// 1. Configure AndroidManifest.xml
if (fs.existsSync(manifestPath)) {
  let manifest = fs.readFileSync(manifestPath, 'utf8');

  // Add permissions for storage and media audio
  const permissions = `
    <!-- KyokoBeat Storage & Media Audio Permissions -->
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
    <uses-permission android:name="android.permission.READ_MEDIA_AUDIO" />
    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE" />
  `;

  // Insert permissions before <application
  if (!manifest.includes('READ_MEDIA_AUDIO')) {
    manifest = manifest.replace('<application', `${permissions}\n    <application`);
    console.log('✓ Injected storage & media permissions into AndroidManifest.xml');
  }

  // Add requestLegacyExternalStorage to application tag
  if (!manifest.includes('android:requestLegacyExternalStorage')) {
    manifest = manifest.replace('<application', '<application android:requestLegacyExternalStorage="true"');
    console.log('✓ Added requestLegacyExternalStorage to application tag');
  }

  fs.writeFileSync(manifestPath, manifest, 'utf8');
} else {
  console.error('Error: AndroidManifest.xml not found at:', manifestPath);
}

// 2. Inject Custom MediaStore Native Plugin into MainActivity.java
if (fs.existsSync(mainActivityPath)) {
  const customMainActivity = `package com.kyokobeat.musicplayer;

import android.Manifest;
import android.content.ContentResolver;
import android.content.ContentUris;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.MediaStore;
import com.getcapacitor.BridgeActivity;
import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.getcapacitor.annotation.Permission;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        registerActivity();
    }
}

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
class KyokoBeatNativePlugin extends Plugin {

    @PluginMethod
    public void checkAndRequestPermissions(PluginCall call) {
        JSObject ret = new JSObject();
        
        if (Build.VERSION.SDK_INT >= 33) { // Android 13+
            if (getPermissionState("audio") != com.getcapacitor.PermissionState.GRANTED) {
                requestPermissionForAlias("audio", call, "permissionCallback");
            } else {
                ret.put("granted", true);
                call.resolve(ret);
            }
        } else { // Android 12 and below
            if (getPermissionState("storage") != com.getcapacitor.PermissionState.GRANTED) {
                requestPermissionForAlias("storage", call, "permissionCallback");
            } else {
                ret.put("granted", true);
                call.resolve(ret);
            }
        }
    }

    @com.getcapacitor.PermissionCallback
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
        String selection = MediaStore.Audio.Media.IS_MUSIC + " != 0";
        String sortOrder = MediaStore.Audio.Media.TITLE + " ASC";
        
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
                    String path = cursor.getString(dataCol);
                    long size = cursor.getLong(sizeCol);
                    long albumId = cursor.getLong(albumIdCol);

                    double durationSecs = durationMs / 1000.0;

                    // Get Album Art Uri
                    Uri sArtworkUri = Uri.parse("content://media/external/audio/albumart");
                    Uri albumArtUri = ContentUris.withAppendedId(sArtworkUri, albumId);

                    JSObject song = new JSObject();
                    song.put("id", "mobile-" + id);
                    song.put("title", title != null ? title : "Unknown Title");
                    song.put("artist", artist == null || artist.equals("<unknown>") ? "Unknown Artist" : artist);
                    song.put("album", album == null || album.equals("<unknown>") ? "Unknown Album" : album);
                    song.put("duration", durationSecs > 0 ? durationSecs : 180.0);
                    song.put("cover", albumArtUri.toString());
                    song.put("path", path);
                    song.put("fileSize", size);
                    song.put("addedAt", System.currentTimeMillis());
                    song.put("isCloud", false);
                    
                    // Generate Capacitor safe web URL for playback
                    String webUrl = "https://localhost/_capacitor_file_" + path;
                    song.put("audioUrl", webUrl);

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

  fs.writeFileSync(mainActivityPath, customMainActivity, 'utf8');
  console.log('✓ Injected custom MediaStore native plugin into MainActivity.java successfully!');
} else {
  console.error('Error: MainActivity.java not found at:', mainActivityPath);
}

console.log('--- Customization Completed successfully ---');
