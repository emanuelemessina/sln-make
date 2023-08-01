$currentFolder = (Get-Location).Path

$currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")

# Check if the current folder is already in the PATH
if ($currentPath -split ";" -contains $currentFolder.Path) {
    Write-Host "Current folder is already in the PATH."
} 
else {
    # Add the current folder to the PATH
    $newPath = "$currentPath;$currentFolder"
    [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
    Write-Host "Current folder added to the PATH successfully."
}
