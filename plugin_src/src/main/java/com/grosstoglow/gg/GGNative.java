package com.grosstoglow.gg;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.media.AudioAttributes;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.VibrationAttributes;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.os.VibratorManager;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.core.content.FileProvider;

import com.google.android.gms.ads.AdError;
import com.google.android.gms.ads.AdRequest;
import com.google.android.gms.ads.FullScreenContentCallback;
import com.google.android.gms.ads.LoadAdError;
import com.google.android.gms.ads.MobileAds;
import com.google.android.gms.ads.RequestConfiguration;
import com.google.android.gms.ads.interstitial.InterstitialAd;
import com.google.android.gms.ads.interstitial.InterstitialAdLoadCallback;
import com.google.android.gms.ads.rewarded.RewardedAd;
import com.google.android.gms.ads.rewarded.RewardedAdLoadCallback;
import com.google.android.ump.ConsentInformation;
import com.google.android.ump.ConsentRequestParameters;
import com.google.android.ump.UserMessagingPlatform;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import java.io.File;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;

/**
 * Plugin nativo do Gross to Glow:
 *  - AdMob: intersticial e premiado (com consentimento UMP antes de pedir anúncios)
 *  - vibração direta pelo Vibrator do Android (com atributos que não são cortados pelo sistema)
 *  - compartilhar imagem pela janela de compartilhar do Android
 */
public class GGNative extends GodotPlugin {
	private static final String TAG = "GGNative";

	private final Handler main = new Handler(Looper.getMainLooper());
	private String interstitialId = "";
	private String rewardedId = "";
	private InterstitialAd interstitial;
	private RewardedAd rewarded;
	private boolean adsStarted = false;
	private boolean loadingInterstitial = false;
	private boolean loadingRewarded = false;

	public GGNative(Godot godot) {
		super(godot);
	}

	@NonNull
	@Override
	public String getPluginName() {
		return "GGNative";
	}

	@NonNull
	@Override
	public Set<SignalInfo> getPluginSignals() {
		return new HashSet<>(Arrays.asList(
				new SignalInfo("ads_ready"),
				new SignalInfo("interstitial_closed"),
				new SignalInfo("rewarded_closed", Boolean.class),
				new SignalInfo("ad_error", String.class)));
	}

	// ------------------------------------------------------------------ anúncios

	/** Pede o consentimento (UMP) e depois inicia o SDK e carrega os anúncios. */
	@UsedByGodot
	public void init_ads(String interstitialUnit, String rewardedUnit) {
		interstitialId = interstitialUnit;
		rewardedId = rewardedUnit;
		final Activity a = getActivity();
		if (a == null) {
			return;
		}
		main.post(() -> {
			try {
				ConsentRequestParameters params = new ConsentRequestParameters.Builder().build();
				final ConsentInformation ci = UserMessagingPlatform.getConsentInformation(a);
				ci.requestConsentInfoUpdate(a, params,
						() -> UserMessagingPlatform.loadAndShowConsentFormIfRequired(a, formError -> {
							if (ci.canRequestAds()) {
								startAds(a);
							}
						}),
						requestError -> startAds(a));
				if (ci.canRequestAds()) {
					startAds(a);
				}
			} catch (Throwable t) {
				Log.w(TAG, "consent", t);
				startAds(a);
			}
		});
	}

	/** Mostra de novo o formulário de privacidade (opções). */
	@UsedByGodot
	public void show_privacy_options() {
		final Activity a = getActivity();
		if (a == null) {
			return;
		}
		main.post(() -> UserMessagingPlatform.showPrivacyOptionsForm(a, e -> {}));
	}

	private void startAds(Activity a) {
		if (adsStarted) {
			return;
		}
		adsStarted = true;
		MobileAds.initialize(a, status -> {
			emitSignal("ads_ready");
			loadInterstitial();
			loadRewarded();
		});
	}

	private void loadInterstitial() {
		final Activity a = getActivity();
		if (a == null || loadingInterstitial || interstitialId.isEmpty()) {
			return;
		}
		loadingInterstitial = true;
		InterstitialAd.load(a, interstitialId, new AdRequest.Builder().build(), new InterstitialAdLoadCallback() {
			@Override
			public void onAdLoaded(@NonNull InterstitialAd ad) {
				loadingInterstitial = false;
				interstitial = ad;
			}

			@Override
			public void onAdFailedToLoad(@NonNull LoadAdError err) {
				loadingInterstitial = false;
				interstitial = null;
				emitSignal("ad_error", "interstitial: " + err.getMessage());
				main.postDelayed(GGNative.this::loadInterstitial, 30000);
			}
		});
	}

	private void loadRewarded() {
		final Activity a = getActivity();
		if (a == null || loadingRewarded || rewardedId.isEmpty()) {
			return;
		}
		loadingRewarded = true;
		RewardedAd.load(a, rewardedId, new AdRequest.Builder().build(), new RewardedAdLoadCallback() {
			@Override
			public void onAdLoaded(@NonNull RewardedAd ad) {
				loadingRewarded = false;
				rewarded = ad;
			}

			@Override
			public void onAdFailedToLoad(@NonNull LoadAdError err) {
				loadingRewarded = false;
				rewarded = null;
				emitSignal("ad_error", "rewarded: " + err.getMessage());
				main.postDelayed(GGNative.this::loadRewarded, 30000);
			}
		});
	}

	@UsedByGodot
	public boolean is_interstitial_ready() {
		return interstitial != null;
	}

	@UsedByGodot
	public boolean is_rewarded_ready() {
		return rewarded != null;
	}

	@UsedByGodot
	public void show_interstitial() {
		final Activity a = getActivity();
		main.post(() -> {
			final InterstitialAd ad = interstitial;
			if (a == null || ad == null) {
				emitSignal("interstitial_closed");
				loadInterstitial();
				return;
			}
			interstitial = null;
			ad.setFullScreenContentCallback(new FullScreenContentCallback() {
				@Override
				public void onAdDismissedFullScreenContent() {
					emitSignal("interstitial_closed");
					loadInterstitial();
				}

				@Override
				public void onAdFailedToShowFullScreenContent(@NonNull AdError e) {
					emitSignal("interstitial_closed");
					loadInterstitial();
				}
			});
			ad.show(a);
		});
	}

	@UsedByGodot
	public void show_rewarded() {
		final Activity a = getActivity();
		main.post(() -> {
			final RewardedAd ad = rewarded;
			if (a == null || ad == null) {
				emitSignal("rewarded_closed", false);
				loadRewarded();
				return;
			}
			rewarded = null;
			final boolean[] earned = {false};
			ad.setFullScreenContentCallback(new FullScreenContentCallback() {
				@Override
				public void onAdDismissedFullScreenContent() {
					emitSignal("rewarded_closed", earned[0]);
					loadRewarded();
				}

				@Override
				public void onAdFailedToShowFullScreenContent(@NonNull AdError e) {
					emitSignal("rewarded_closed", false);
					loadRewarded();
				}
			});
			ad.show(a, rewardItem -> earned[0] = true);
		});
	}

	// ------------------------------------------------------------------ vibração

	private Vibrator vibrator() {
		Activity a = getActivity();
		if (a == null) {
			return null;
		}
		if (Build.VERSION.SDK_INT >= 31) {
			VibratorManager vm = (VibratorManager) a.getSystemService(Context.VIBRATOR_MANAGER_SERVICE);
			return vm != null ? vm.getDefaultVibrator() : null;
		}
		return (Vibrator) a.getSystemService(Context.VIBRATOR_SERVICE);
	}

	/**
	 * Vibra direto pelo Android. amplitude 1..255 (ou -1 = padrão do aparelho).
	 * Usa atributo de ALARME: a vibração "de mídia" (a padrão dos jogos) vem desligada em muitos celulares.
	 */
	@UsedByGodot
	public void vibrate(int ms, int amplitude) {
		try {
			Vibrator v = vibrator();
			if (v == null || !v.hasVibrator()) {
				return;
			}
			if (Build.VERSION.SDK_INT >= 26) {
				int amp = amplitude <= 0 || !v.hasAmplitudeControl() ? VibrationEffect.DEFAULT_AMPLITUDE : Math.min(255, amplitude);
				VibrationEffect fx = VibrationEffect.createOneShot(Math.max(1, ms), amp);
				if (Build.VERSION.SDK_INT >= 33) {
					v.vibrate(fx, VibrationAttributes.createForUsage(VibrationAttributes.USAGE_ALARM));
				} else {
					v.vibrate(fx, new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build());
				}
			} else {
				v.vibrate(ms);
			}
		} catch (Throwable t) {
			Log.w(TAG, "vibrate", t);
		}
	}

	// ------------------------------------------------------------------ compartilhar

	/** Abre a janela de compartilhar do Android com a imagem (caminho absoluto, dentro de user://). */
	@UsedByGodot
	public boolean share_image(String path, String text) {
		final Activity a = getActivity();
		if (a == null) {
			return false;
		}
		try {
			File f = new File(path);
			Uri uri = FileProvider.getUriForFile(a, a.getPackageName() + ".fileprovider", f);
			Intent send = new Intent(Intent.ACTION_SEND);
			send.setType("image/png");
			send.putExtra(Intent.EXTRA_STREAM, uri);
			send.putExtra(Intent.EXTRA_TEXT, text);
			send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
			Intent chooser = Intent.createChooser(send, null);
			chooser.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
			main.post(() -> a.startActivity(chooser));
			return true;
		} catch (Throwable t) {
			Log.w(TAG, "share", t);
			return false;
		}
	}
}
