/// Marque compilée (splash, launcher). Surcharge : `--dart-define=APP_NAME=…`
const String kAppName = String.fromEnvironment(
  'APP_NAME',
  defaultValue: 'NeoForma',
);

/// Dictée / micro (saisie vocale). Masquée : clavier et champs restent.
bool get kVoiceInputEnabled => false;
