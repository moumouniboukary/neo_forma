import type { Config } from "@capacitor/cli";

const config: Config = {
  appId: "bf.neoforma.app",
  appName: "NeoForma",
  webDir: "dist",
  server: {
    androidScheme: "https",
    // En dev natif, pointer vers le PC (décommenter) :
    // url: "http://192.168.1.10:5173",
    // cleartext: true,
  },
  plugins: {
    SplashScreen: {
      launchAutoHide: true,
      backgroundColor: "#07140F",
    },
  },
};

export default config;
