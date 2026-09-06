#Requires -Version 5.1
<#
.SYNOPSIS
  Génère les WAV FR (System.Speech) pour VoiceService — fallback si edge-tts indisponible.
#>
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Speech

$Root = Split-Path -Parent $PSScriptRoot
$FrDir = Join-Path $Root "apps\mobile\assets\audio\fr"
New-Item -ItemType Directory -Force -Path $FrDir | Out-Null

$Phrases = @{
  activateScore = "Activez votre NeoScore"
  allow = "Autoriser"
  amount = "Montant"
  back = "Retour"
  chooseLanguage = "Choisissez votre langue"
  client = "Client"
  confirm = "Confirmer"
  continue = "Continuer"
  createAccount = "Créer un compte"
  credit = "Crédit"
  debts = "Dettes"
  deny = "Refuser"
  displayName = "Nom affiché"
  eligible = "Éligible"
  entrepreneur = "Entrepreneur"
  expense = "Dépense"
  hello = "Bonjour"
  helloName = "Bonjour"
  home = "Accueil"
  iconMode = "Mode icônes"
  language = "Langue"
  ledger = "Cahier"
  listen = "Écouter"
  login = "Connexion"
  logout = "Déconnexion"
  neoscore = "NeoScore"
  newAccount = "Nouveau compte"
  next = "Suivant"
  notEligible = "Non éligible"
  overdue = "En retard"
  phone = "Téléphone"
  pinCode = "Code PIN"
  profile = "Profil"
  quickActions = "Actions rapides"
  receivable = "Créance"
  receiveCode = "Recevoir le code"
  record = "Enregistrer"
  register = "Inscription"
  sale = "Vente"
  salesMonth = "Ventes du mois"
  save = "Enregistrer"
  shareImf = "Partage IMF"
  smsCode = "Code SMS"
  stock = "Stock"
  submitCredit = "Soumettre la demande de crédit"
  toCollect = "À encaisser"
  voiceAssist = "Assistance vocale"
  yourActivity = "Votre activité"
}

$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
try {
  $fr = $synth.GetInstalledVoices() | Where-Object {
    $_.VoiceInfo.Culture.Name -like "fr*"
  } | Select-Object -First 1
  if ($fr) {
    $synth.SelectVoice($fr.VoiceInfo.Name)
  }
  $synth.Rate = -1
  $synth.Volume = 100

  $ok = 0
  foreach ($key in ($Phrases.Keys | Sort-Object)) {
    $out = Join-Path $FrDir "$key.wav"
    $synth.SetOutputToWaveFile($out)
    $synth.Speak($Phrases[$key])
    $synth.SetOutputToNull()
    if (Test-Path $out) {
      $ok++
      Write-Host "OK $key"
    }
  }
  Write-Host "FR audio: $ok / $($Phrases.Count) fichiers dans $FrDir"
} finally {
  $synth.Dispose()
}
