[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RepositoryRoot,
    # Destino por defecto: el perfil del usuario de la sesion. Nunca se
    # hardcodea `C:\Users\<usuario>`; cada maquina puede tener otro nombre.
    [string]$DestinationRoot = $env:USERPROFILE,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

Import-Module (Join-Path $RepositoryRoot 'modules/SetupHelpers.psm1') -Force

Write-SetupStep 'Preparando repos personales'

if (-not $DestinationRoot) {
    Write-SetupError 'No se pudo resolver el perfil del usuario (USERPROFILE vacio).'
    return
}

$listPath = Join-Path $RepositoryRoot 'repos/personal-repos.txt'
if (-not (Test-Path -LiteralPath $listPath)) {
    Write-SetupWarning "No existe la lista de repos ($listPath). Se omite la etapa."
    return
}

try {
    Test-CommandAvailable -Name 'git'
}
catch {
    Write-SetupError 'Git no esta disponible.'
    Write-SetupWarning 'Instalalo con la etapa de apps (Git.Git) y volve a correr esta etapa.'
    return
}

Write-SetupInfo "git     : $((git --version) 2>&1)"
Write-SetupInfo "Destino : $DestinationRoot"

# Lee la lista: una URL por linea, `#` comentarios, `owner/repo` como atajo.
$repos = @()
foreach ($rawLine in Get-Content -LiteralPath $listPath) {
    $line = $rawLine.Trim()
    if (-not $line -or $line.StartsWith('#')) {
        continue
    }

    $url = $line
    if ($line -notmatch '^[a-z]+://') {
        $url = "https://github.com/$line"
    }

    $name = ($url.TrimEnd('/') -split '/')[-1]
    if ($name -match '\.git$') {
        $name = $name.Substring(0, $name.Length - 4)
    }

    if (-not $name) {
        Write-SetupWarning "URL sin nombre de repo, se omite: $line"
        continue
    }

    $repos += [pscustomobject]@{
        Url    = $url
        Name   = $name
        Target = (Join-Path $DestinationRoot $name)
    }
}

if ($repos.Count -eq 0) {
    Write-SetupWarning "La lista $listPath no tiene ningun repo."
    return
}

$cloned = 0
$pulled = 0
$skipped = 0
$failed = 0

# GIT_TERMINAL_PROMPT=0 evita que un `git clone` sin credenciales se quede
# colgado esperando usuario/password en la consola y trabe todo el setup.
# Git Credential Manager (credential.helper=manager) usa GUI/navegador, asi que
# sigue funcionando igual; si no hay credenciales, falla rapido y con mensaje.
$previousPrompt = $env:GIT_TERMINAL_PROMPT
$env:GIT_TERMINAL_PROMPT = '0'

try {
    foreach ($repo in $repos) {
        $exists = Test-Path -LiteralPath $repo.Target

        if ($DryRun) {
            if ($exists) {
                Write-SetupInfo "[dry run] ya existe, haria 'git pull --ff-only': $($repo.Target)"
            }
            else {
                Write-SetupInfo "[dry run] haria 'git clone $($repo.Url)': $($repo.Target)"
            }
            continue
        }

        if ($exists) {
            if (-not (Test-Path -LiteralPath (Join-Path $repo.Target '.git'))) {
                # Una carpeta con el mismo nombre pero sin repo adentro no se
                # toca: borrarla o pisarla puede destruir datos del usuario.
                Write-SetupWarning "Ya existe y no es un repo git, no se toca: $($repo.Target)"
                $skipped++
                continue
            }

            Write-SetupProgress -Activity 'Repos personales' -Status "git pull: $($repo.Name)"
            $output = (& git -C $repo.Target pull --ff-only 2>&1 | Out-String)
            $exitCode = $LASTEXITCODE
            Clear-SetupProgress

            if ($exitCode -eq 0) {
                Write-SetupSuccess "Actualizado: $($repo.Name)"
                $pulled++
            }
            else {
                # Tolerante a proposito: un repo roto (divergencia, sin red) no
                # puede abortar el resto del setup.
                Write-SetupWarning "No se pudo actualizar $($repo.Name) (exit $exitCode)."
                $output.Trim() -split "`r?`n" | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
                $failed++
            }
            continue
        }

        Write-SetupProgress -Activity 'Repos personales' -Status "git clone: $($repo.Name)"
        $output = (& git clone --quiet $repo.Url $repo.Target 2>&1 | Out-String)
        $exitCode = $LASTEXITCODE
        Clear-SetupProgress

        if ($exitCode -eq 0) {
            Write-SetupSuccess "Clonado: $($repo.Name) -> $($repo.Target)"
            $cloned++
        }
        else {
            Write-SetupWarning "No se pudo clonar $($repo.Url) (exit $exitCode)."
            $output.Trim() -split "`r?`n" | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
            if ($output -match 'Authentication failed|could not read Username|terminal prompts disabled|Repository not found') {
                Write-SetupInfo 'Parece un repo privado sin credenciales. Autentica una vez con Git Credential Manager y volve a correr la etapa; no se guardan tokens en el repo.'
            }
            $failed++
        }
    }
}
finally {
    if ($null -eq $previousPrompt) {
        Remove-Item Env:GIT_TERMINAL_PROMPT -ErrorAction SilentlyContinue
    }
    else {
        $env:GIT_TERMINAL_PROMPT = $previousPrompt
    }
}

Write-SetupRule
Write-SetupInfo "Clonados: $cloned | Actualizados: $pulled | Omitidos: $skipped | Fallidos: $failed"

if ($DryRun) {
    Write-SetupSuccess 'Dry run completado (no se toco ningun repo).'
}
elseif ($failed -gt 0) {
    Write-SetupWarning 'Algunos repos no quedaron listos; el resto del setup sigue igual.'
}
else {
    Write-SetupSuccess 'Repos personales listos.'
}
