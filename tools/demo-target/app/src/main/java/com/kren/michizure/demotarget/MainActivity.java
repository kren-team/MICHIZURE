package com.kren.michizure.demotarget;

import android.app.Activity;
import android.graphics.Color;
import android.os.Bundle;
import android.view.Gravity;
import android.widget.LinearLayout;
import android.widget.TextView;

public final class MainActivity extends Activity {
  @Override
  protected void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);

    LinearLayout content = new LinearLayout(this);
    content.setGravity(Gravity.CENTER);
    content.setOrientation(LinearLayout.VERTICAL);
    content.setPadding(48, 48, 48, 48);

    TextView title = new TextView(this);
    title.setText("MICHIZURE Demo Target");
    title.setTextColor(Color.rgb(35, 35, 45));
    title.setTextSize(24);
    title.setGravity(Gravity.CENTER);
    content.addView(title);

    TextView description = new TextView(this);
    description.setText("封印と解除を安全に確認するための、データを持たないデモ専用アプリです。");
    description.setTextColor(Color.DKGRAY);
    description.setTextSize(16);
    description.setGravity(Gravity.CENTER);
    description.setPadding(0, 32, 0, 0);
    content.addView(description);

    setContentView(content);
  }
}
