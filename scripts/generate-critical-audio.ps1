#Requires -Version 5.1
<#
.SYNOPSIS
  Génère les WAV critiques FR + MR (System.Speech) pour flux illettrés.
#>
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Speech

$Root = Split-Path -Parent $PSScriptRoot
$FrDir = Join-Path $Root "apps\mobile\assets\audio\fr"
$MrDir = Join-Path $Root "apps\mobile\assets\audio\mr"
New-Item -ItemType Directory -Force -Path $FrDir | Out-Null
New-Item -ItemType Directory -Force -Path $MrDir | Out-Null

$Fr = @{
  askAmount = "Combien ?"
  confirmAmountPrompt = "Confirmer ce montant ?"
  confirmAmount = "Confirmer"
  dictInFrench = "Dites le montant en français"
  dictAmountFail = "Montant non compris. Réessayez."
  chooseProduct = "Choisissez un produit"
  chooseClient = "Choisissez un client"
  chooseType = "Choisissez le type d opération"
  chooseCategory = "Choisissez une catégorie"
  chooseStockNature = "Entrée ou sortie de stock ?"
  stockIn = "Entrée"
  stockOut = "Sortie"
  stockLow = "Stock bas"
  addArticle = "Ajouter un article"
  askArticleName = "Quel article ?"
  askQuantity = "Quelle quantité ?"
  askUnitPrice = "Quel prix unitaire ?"
  confirmArticle = "Confirmer cet article ?"
  dictName = "Dicter le nom"
  dictNameFail = "Nom non compris. Réessayez."
  phoneEnter = "Tapez votre numéro. Huit chiffres."
  phone = "Téléphone"
  recordSuccess = "Enregistré. C est bon."
  voiceGuideStart = "Saisie à la voix"
  otpAgentHint = "Montrez ce code à la personne qui aide"
  otpListen = "Écouter le code"
  yes = "Oui"
  no = "Non"
  keepOp = "Garder"
  deleteOp = "Supprimer"
  confirmDeleteOp = "Supprimer cette opération ?"
  pinBigHint = "Tapez votre code à quatre chiffres"
  enableBiometric = "Utiliser l empreinte ou le visage"
  enterPin = "Entrez votre code PIN"
  appLocked = "Application verrouillée"
  lockedTryLater = "Trop de tentatives. Réessayez plus tard."
  wrongPin = "Code PIN incorrect"
  useBiometric = "Utiliser la biométrie"
}

$Mr = @{
  askAmount = "Wãnã ligdi ?"
  confirmAmountPrompt = "Tõe ligdi kanga ?"
  confirmAmount = "Tõe"
  dictInFrench = "Yẽese ligdi ne français"
  dictAmountFail = "Ligdi ka wʋm. Maan zĩiri."
  chooseProduct = "Sõsg bũumbu"
  chooseClient = "Sõsg client"
  chooseType = "Sõsg tõe sõrẽ"
  chooseCategory = "Sõsg sõrẽ"
  chooseStockNature = "Kẽesgo bɩ yiisgo ?"
  stockIn = "Kẽesgo"
  stockOut = "Yiisgo"
  stockLow = "Stock ka toe"
  addArticle = "Paas bũumbu"
  askArticleName = "Bũumbu bẽnẽ ?"
  askQuantity = "Sõmblem wãnã ?"
  askUnitPrice = "Ligdi a ye wãnã ?"
  confirmArticle = "Tõe bũumbu kanga ?"
  dictName = "Yẽese yʋʋre"
  dictNameFail = "Yʋʋre ka wʋm. Maan zĩiri."
  phoneEnter = "Sẽnseg nombure 8"
  phone = "Telefon"
  recordSuccess = "Gomame. Yaa tõe."
  voiceGuideStart = "Gom ne gũusu"
  otpAgentHint = "Wʋl kode ne collaborateur"
  otpListen = "Wʋm kode"
  yes = "Yaa"
  no = "Ayi"
  keepOp = "Kẽese"
  deleteOp = "Yĩise"
  confirmDeleteOp = "Yĩise tõe kanga ?"
  pinBigHint = "Sẽnseg PIN nombure naase"
  enableBiometric = "Tũ biometri"
  enterPin = "Sẽnseg fõ PIN"
  appLocked = "Aplikasion yagame"
  lockedTryLater = "Maaneg wʋsg. Maan poore."
  wrongPin = "PIN pa tɩrga"
  useBiometric = "Tũ biometri"
}

function Write-Phrases([string]$Dir, [hashtable]$Phrases, $Synth) {
  $n = 0
  foreach ($key in ($Phrases.Keys | Sort-Object)) {
    $out = Join-Path $Dir "$key.wav"
    $Synth.SetOutputToWaveFile($out)
    $Synth.Speak($Phrases[$key])
    $Synth.SetOutputToNull()
    $n++
    Write-Host "  $key.wav"
  }
  return $n
}

$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
try {
  $frVoice = $synth.GetInstalledVoices() | Where-Object {
    $_.VoiceInfo.Culture.Name -like "fr*"
  } | Select-Object -First 1
  if ($frVoice) {
    $synth.SelectVoice($frVoice.VoiceInfo.Name)
  }
  $synth.Rate = -1
  $synth.Volume = 100

  Write-Host "FR -> $FrDir"
  $a = Write-Phrases $FrDir $Fr $synth
  Write-Host "MR -> $MrDir"
  $b = Write-Phrases $MrDir $Mr $synth
  Write-Host "OK: $a FR + $b MR WAV"
} finally {
  $synth.Dispose()
}
