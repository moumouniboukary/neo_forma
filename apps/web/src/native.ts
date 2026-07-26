import { Capacitor } from "@capacitor/core";
import { Network } from "@capacitor/network";
import { App as CapApp } from "@capacitor/app";

/** Hooks natifs optionnels — no-op dans le navigateur / PWA. */
export async function initNativeShell() {
  if (!Capacitor.isNativePlatform()) return;

  CapApp.addListener("backButton", ({ canGoBack }) => {
    if (canGoBack) window.history.back();
    else void CapApp.exitApp();
  });

  Network.addListener("networkStatusChange", (status) => {
    window.dispatchEvent(
      new CustomEvent("neoforma:network", { detail: status.connected })
    );
  });
}
