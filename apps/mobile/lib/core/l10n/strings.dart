/// Libellés FR / Mooré (mr).
/// Les traductions mooré sont un MVP à valider avec des locuteurs natifs.
class NfStrings {
  NfStrings(this.lang);

  final String lang; // fr | mr

  static const languageLabels = {'fr': 'Français', 'mr': 'Mooré'};

  /// Langues proposées dans l’UI (français + mooré uniquement).
  static List<(String, String)> get selectableLanguages => [
    for (final e in languageLabels.entries) (e.key, e.value),
  ];

  /// Normalise une langue persistée (ex. ancien `dl`) vers fr ou mr.
  static String normalize(String? code) {
    if (code == 'mr') return 'mr';
    return 'fr';
  }

  String get(String key) {
    final table = _tables[normalize(lang)]!;
    return table[key] ?? _tables['fr']![key] ?? key;
  }

  String call(String key) => get(key);

  static const Map<String, Map<String, String>> _tables = {
    'fr': {
      'appName': 'NeoForma',
      'hello': 'Bonjour',
      'helloName': 'Bonjour, {name}',
      'home': 'Accueil',
      'ledger': 'Cahier',
      'debts': 'Créances',
      'profile': 'Profil',
      'register': 'Inscription',
      'newAccount': 'Nouveau compte',
      'phone': 'Téléphone',
      'smsCode': 'Code SMS',
      'pinCode': 'Code PIN',
      'displayName': 'Prénom / nom',
      'displayNameHint': 'Ex. Awa Ouédraogo',
      'createAccount': 'Créer le compte',
      'receiveCode': 'Recevoir le code',
      'continue': 'Continuer',
      'language': 'Langue',
      'iconMode': 'Mode icônes',
      'iconModeHint': 'Boutons plus grands, moins de texte',
      'salesMonth': 'Ventes ce mois',
      'toCollect': 'À récupérer',
      'overdue': 'En retard',
      'quickActions': 'Actions rapides',
      'record': 'Enregistrer',
      'credit': 'Crédit',
      'neoscore': 'NeoScore',
      'yourActivity': 'Ton activité',
      'activateScore': 'Activer mon NeoScore',
      'save': 'Enregistrer',
      'logout': 'Se déconnecter',
      'shareImf': 'Partage avec les IMF',
      'allow': 'Autoriser',
      'deny': 'Refuser',
      'sale': 'Vente',
      'stock': 'Stock',
      'receivable': 'Créance',
      'expense': 'Dépense',
      'confirm': 'Confirmer',
      'amount': 'Montant (FCFA)',
      'client': 'Client',
      'offlineQueue': 'File hors ligne',
      'offlineUpToDate': 'à jour',
      'offlinePending': '{n} en attente',
      'entrepreneur': 'Entrepreneur',
      'chooseLanguage': 'Choisir la langue',
      'next': 'Suivant',
      'back': 'Retour',
      'voiceAssist': 'Assistance vocale',
      'voiceAssistHint': 'Écouter les libellés (bouton haut-parleur)',
      'listen': 'Écouter',
      'login': 'Connexion',
      'eligible': 'Profil éligible',
      'notEligible': 'Pas encore éligible',
      'submitCredit': 'Soumettre la demande',
    },
    'mr': {
      'appName': 'NeoForma',
      'hello': 'Ne y yibeogo',
      'helloName': 'Ne y yibeogo, {name}',
      'home': 'Yĩnga',
      'ledger': 'Gom-nate',
      'debts': 'Sẽga',
      'profile': 'Menga',
      'register': 'Sõng-n yẽ',
      'newAccount': 'Konti paalga',
      'phone': 'Telefon',
      'smsCode': 'SMS kode',
      'pinCode': 'PIN kode',
      'displayName': 'Yũure',
      'displayNameHint': 'Ex. Awa Ouédraogo',
      'createAccount': 'Maana konti',
      'receiveCode': 'De kode',
      'continue': 'Tõoke',
      'language': 'Goama',
      'iconMode': 'Bũumbu mode',
      'iconModeHint': 'Bouton-damba, gom-biisgo',
      'salesMonth': 'Kõeesgo wãtẽ',
      'toCollect': 'Sẽga n de',
      'overdue': 'Yẽnde',
      'quickActions': 'Tõe-tõe',
      'record': 'Gom-nate',
      'credit': 'Kredit',
      'neoscore': 'NeoScore',
      'yourActivity': 'Fõ tõe',
      'activateScore': 'Neoge NeoScore',
      'save': 'Jãnga',
      'logout': 'Yi',
      'shareImf': 'IMF tõe',
      'allow': 'Sõnga',
      'deny': 'Tõe ye',
      'sale': 'Kõeesgo',
      'stock': 'Stock',
      'receivable': 'Sẽga',
      'expense': 'Rẽem',
      'confirm': 'Tõe',
      'amount': 'Ligdi (FCFA)',
      'client': 'Kient',
      'offlineQueue': 'Offline file',
      'offlineUpToDate': 'sõma',
      'offlinePending': '{n} n pa',
      'entrepreneur': 'Tõe-soba',
      'chooseLanguage': 'Baasa goama',
      'next': 'Tõoke',
      'back': 'Lebge',
      'voiceAssist': 'Goama n wʋm',
      'voiceAssistHint': 'Wʋm gom-nate (bũumbu speaker)',
      'listen': 'Wʋm',
      'login': 'Kẽ',
      'eligible': 'Sõma',
      'notEligible': 'Pa sõma yee',
      'submitCredit': 'Tõe kredit',
    },
  };

  String format(String key, Map<String, String> vars) {
    var s = get(key);
    for (final e in vars.entries) {
      s = s.replaceAll('{${e.key}}', e.value);
    }
    return s;
  }
}
