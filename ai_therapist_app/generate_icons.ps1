Write-Host "Generating app icons for the AI Therapist App..." -ForegroundColor Green

# Create necessary directories if they don't exist
New-Item -ItemType Directory -Force -Path "ai_therapist_app\assets\icons" | Out-Null

# Change to the app directory
Set-Location -Path ai_therapist_app

# Run flutter pub get to ensure dependencies
Write-Host "Ensuring dependencies are up to date..." -ForegroundColor Yellow
flutter pub get

# Generate the icons using flutter_launcher_icons
Write-Host "Generating icons with flutter_launcher_icons..." -ForegroundColor Yellow
flutter pub run flutter_launcher_icons:main

Write-Host "Icon generation completed!" -ForegroundColor Green
Write-Host "App is using the theme colors:" -ForegroundColor Cyan
Write-Host "  Primary: #5E72E4 (Indigo blue)" -ForegroundColor Cyan
Write-Host "  Secondary: #11CDEF (Cyan)" -ForegroundColor Cyan
Write-Host "  Accent: #FB6340 (Orange)" -ForegroundColor Cyan

# Return to the original directory
Set-Location -Path ..

Write-Host "Done!" -ForegroundColor Green 