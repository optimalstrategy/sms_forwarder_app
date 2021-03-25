package team.whatever.sms_forwarder_app;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Handler;


import static android.content.Context.MODE_PRIVATE;

class StartSmsForwarderServiceAtBootReceiver extends BroadcastReceiver {
    private static final String TAG = StartSmsForwarderServiceAtBootReceiver.class.getSimpleName();

    @Override
    public void onReceive(Context context, Intent intent) {
        Handler h = new Handler();
        h.post(new Runnable() {
            @Override
            public void run() {
                final SharedPreferences prefs = context.getSharedPreferences(
                        "FlutterSharedPreferences",
                        MODE_PRIVATE
                );
                final boolean launchOnStartup = prefs.getBoolean("flutter.launch_on_startup", true);
                if (launchOnStartup) {
                    Intent intent_ = new Intent(context, MainActivity.class);
                    intent_.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                    context.startActivity(intent_);
                }
            }
        });
    }
}