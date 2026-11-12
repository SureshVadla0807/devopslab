$ErrorActionPreference = 'Stop'

# DevOps Lab generator for Windows PowerShell 5.1 / PowerShell 7
$Desktop = [Environment]::GetFolderPath('Desktop')
if ([string]::IsNullOrWhiteSpace($Desktop)) {
    $Desktop = Join-Path $HOME 'Desktop'
}
$Root = Join-Path $Desktop 'DevOps Lab'
$Exp1 = Join-Path $Root '1. Event Registration Form'
$Exp2 = Join-Path $Root '2. Git and GitHub Commands'
$Exp3 = Join-Path $Root '3. GitHub Source Code Management'
$Exp5 = Join-Path $Root '5. Jenkins CI-CD Integration'
$Exp6 = Join-Path $Root '6. Docker Commands'
$Exp7 = Join-Path $Root '7. Docker Containerized Application'
$Exp11 = Join-Path $Root '11. JavaScript Selenium Testing'
$Exp12 = Join-Path $Root '12. Selenium Test Cases'

New-Item -ItemType Directory -Path $Root -Force | Out-Null

function Write-Title {
    param([string]$Title)
    Write-Host "`n========== $Title ==========" -ForegroundColor Cyan
}

function Pause-Menu {
    [void](Read-Host 'Press Enter to return to the menu')
}

function Write-TextFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $utf8NoBom = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList @($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Open-TextFile {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        Start-Process -FilePath 'notepad.exe' -ArgumentList ('"{0}"' -f $Path)
    }
}

function Ensure-Git {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'Git is not installed or is not in PATH. Install Git for Windows, reopen PowerShell, and try again.'
    }
}

function Invoke-Git {
    param([Parameter(Mandatory = $true)][string[]]$GitArgs)
    & git @GitArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Git command failed: git $($GitArgs -join ' ')"
    }
}

function Ensure-SupportedNode {
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        throw 'Node.js is not installed. Install a supported Node.js version and reopen PowerShell.'
    }
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        throw 'npm is not available. Repair or reinstall Node.js.'
    }

    $versionText = (& node -p 'process.versions.node').Trim()
    try { $nodeVersion = [version]$versionText } catch { throw "Could not read Node.js version: $versionText" }

    $supported = $false
    if ($nodeVersion.Major -eq 22 -and $nodeVersion -ge [version]'22.23.4') { $supported = $true }
    if ($nodeVersion.Major -eq 24 -and $nodeVersion -ge [version]'24.22.1') { $supported = $true }
    if ($nodeVersion.Major -eq 26 -and $nodeVersion -ge [version]'26.12.1') { $supported = $true }

    if (-not $supported) {
        throw "Installed Node.js is $versionText. Current Selenium JavaScript bindings require Node.js 22.23.4+, 24.22.1+, or 26.12.1+ (within those major versions)."
    }
    Write-Host "Node.js $versionText detected." -ForegroundColor Green
}

function Ensure-DockerEngine {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'Docker CLI was not found. Install Docker Desktop first.'
    }

    docker info *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-Host 'Docker Engine is already running.' -ForegroundColor Green
        return
    }

    Write-Host 'Docker Engine is not running. Starting Docker Desktop...' -ForegroundColor Yellow
    $desktopCandidates = @(
        (Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Docker\Docker\Docker Desktop.exe')
    )
    $dockerDesktop = $desktopCandidates |
        Where-Object { $_ -and (Test-Path -LiteralPath $_) } |
        Select-Object -First 1

    if (-not $dockerDesktop) {
        throw 'Docker Desktop executable was not found. Open Docker Desktop manually and retry.'
    }

    Start-Process -FilePath $dockerDesktop
    $ready = $false
    for ($i = 1; $i -le 40; $i++) {
        Start-Sleep -Seconds 3
        docker info *> $null
        if ($LASTEXITCODE -eq 0) {
            $ready = $true
            break
        }
        Write-Host "Waiting for Docker Engine... ($i/40)"
    }

    if (-not $ready) {
        throw 'Docker Engine did not become ready within 120 seconds. Check Docker Desktop, WSL 2, and virtualization.'
    }
    Write-Host 'Docker Engine is ready.' -ForegroundColor Green
}

function Get-DevOpsContainerId {
    $id = & docker ps -aq --filter 'name=^/devops-lab-app$'
    if ($LASTEXITCODE -ne 0) { throw 'Could not query Docker containers.' }
    if ($id) { return ([string]($id | Select-Object -First 1)).Trim() }
    return $null
}

function Test-DevOpsContainerRunning {
    $id = & docker ps -q --filter 'name=^/devops-lab-app$'
    if ($LASTEXITCODE -ne 0) { throw 'Could not query running Docker containers.' }
    return [bool]$id
}

function Clear-Experiment6PortConflict {
    # Experiment 6's optional Nginx container also uses host port 8000.
    $portUsers = & docker ps --filter 'publish=8000' --format '{{.Names}}'
    if ($LASTEXITCODE -ne 0) { throw 'Could not check Docker port 8000 usage.' }
    foreach ($name in @($portUsers)) {
        if ([string]::IsNullOrWhiteSpace($name) -or $name -eq 'devops-lab-app') { continue }
        if ($name -eq 'mynginx') {
            Write-Host 'Stopping Experiment 6 Nginx container to free port 8000...' -ForegroundColor Yellow
            docker rm -f mynginx
            if ($LASTEXITCODE -ne 0) { throw 'Could not remove the Experiment 6 mynginx container.' }
        } else {
            throw "Port 8000 is already used by Docker container '$name'. Stop it before starting the DevOps Lab application."
        }
    }
}

function Wait-ForDockerApp {
    $ready = $false
    for ($i = 1; $i -le 20; $i++) {
        try {
            $response = Invoke-WebRequest -Uri 'http://localhost:8000' -UseBasicParsing -TimeoutSec 3
            if ($response.StatusCode -eq 200) {
                $ready = $true
                break
            }
        } catch {
            Start-Sleep -Seconds 2
        }
    }
    if (-not $ready) {
        Write-Host 'Recent container logs:' -ForegroundColor Yellow
        docker logs --tail 30 devops-lab-app
        throw 'The application did not respond at http://localhost:8000. Check the container and whether port 8000 is already in use.'
    }
}

function Get-Experiment7Html {
    return @'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Docker Application</title>
</head>
<body>
    <h2>DevOps Lab - Docker Application</h2>
    <p>Container is running successfully!</p>
    <input id="name" type="text" placeholder="Enter your name">
    <button id="greetButton" type="button" onclick="showGreeting()">Submit</button>
    <p id="greeting"></p>
    <script>
        function showGreeting() {
            const name = document.getElementById('name').value.trim();
            document.getElementById('greeting').textContent = name
                ? 'Hello ' + name + '! Welcome to Docker.'
                : 'Please enter your name.';
        }
    </script>
</body>
</html>
'@
}

function Ensure-Experiment7Files {
    param([switch]$Overwrite)
    New-Item -ItemType Directory -Path $Exp7 -Force | Out-Null

    $htmlPath = Join-Path $Exp7 'index.html'
    $dockerfilePath = Join-Path $Exp7 'Dockerfile'
    $commandsPath = Join-Path $Exp7 'docker_commands.txt'
    $manualPath = Join-Path $Exp7 'manual.txt'

    $html = Get-Experiment7Html
    $dockerfile = @'
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
'@
    $commands = @'
EXPERIMENT 7 - DOCKER COMMANDS

Run these commands from the Experiment 7 folder:

docker build -t devops-lab-app .
docker run -d -p 8000:80 --name devops-lab-app devops-lab-app
docker ps
docker logs devops-lab-app

Open the application:
http://localhost:8000

Container management:
docker stop devops-lab-app
docker start devops-lab-app
docker restart devops-lab-app
docker rm -f devops-lab-app
docker rmi devops-lab-app

Port mapping: host port 8000 -> container port 80.
If the Experiment 6 mynginx container is running, the automated Experiment 7 workflow removes it to free port 8000.
If another application/container uses port 8000, stop it before running this container.
'@
    $manual = @'
EXPERIMENT 7 - MANUAL EXECUTION

1. Start Docker Desktop and wait until Docker Engine is running.
2. Open PowerShell and run:

$desktop = [Environment]::GetFolderPath('Desktop')
Set-Location (Join-Path $desktop 'DevOps Lab\7. Docker Containerized Application')
docker build -t devops-lab-app .
docker run -d -p 8000:80 --name devops-lab-app devops-lab-app
docker ps

3. Open:
http://localhost:8000

4. View logs:
docker logs devops-lab-app

5. Stop, start, or remove the container:
docker stop devops-lab-app
docker start devops-lab-app
docker rm -f devops-lab-app

If the container name already exists, remove the old container before running docker run again:
docker rm -f devops-lab-app
'@

    if ($Overwrite -or -not (Test-Path -LiteralPath $htmlPath)) { Write-TextFile $htmlPath $html }
    if ($Overwrite -or -not (Test-Path -LiteralPath $dockerfilePath)) { Write-TextFile $dockerfilePath $dockerfile }
    if ($Overwrite -or -not (Test-Path -LiteralPath $commandsPath)) { Write-TextFile $commandsPath $commands }
    if ($Overwrite -or -not (Test-Path -LiteralPath $manualPath)) { Write-TextFile $manualPath $manual }
}

function Ensure-DockerApp {
    param([switch]$Rebuild)
    Ensure-Experiment7Files
    Ensure-DockerEngine

    $containerId = Get-DevOpsContainerId
    if ($Rebuild -and $containerId) {
        docker rm -f devops-lab-app
        if ($LASTEXITCODE -ne 0) { throw 'Could not remove the previous application container.' }
        $containerId = $null
    }

    Clear-Experiment6PortConflict

    if (-not $containerId) {
        Write-Host 'Building the Experiment 7 Docker image...' -ForegroundColor Cyan
        Push-Location $Exp7
        try {
            docker build -t devops-lab-app .
            if ($LASTEXITCODE -ne 0) { throw 'Docker image build failed.' }
            docker run -d -p 8000:80 --name devops-lab-app devops-lab-app
            if ($LASTEXITCODE -ne 0) {
                throw 'Docker container failed to start. Check whether host port 8000 is already in use.'
            }
        } finally {
            Pop-Location
        }
    } elseif (-not (Test-DevOpsContainerRunning)) {
        Write-Host 'Starting the existing Experiment 7 container...' -ForegroundColor Cyan
        docker start devops-lab-app
        if ($LASTEXITCODE -ne 0) { throw 'Could not start the existing Docker container.' }
    }

    Wait-ForDockerApp
    Write-Host 'Docker application is available at http://localhost:8000.' -ForegroundColor Green
}

function New-Experiment1 {
    param([switch]$OpenBrowser)
    New-Item -ItemType Directory -Path $Exp1 -Force | Out-Null
    $htmlPath = Join-Path $Exp1 'index.html'
    $manualPath = Join-Path $Exp1 'manual.txt'

    $html = @'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Event Registration</title>
</head>
<body>
    <h2>Event Registration Form</h2>
    <form id="registrationForm">
        <label>Name: <input id="name" required></label><br><br>
        <label>Email: <input id="email" type="email" required></label><br><br>
        <label>Event:
            <select id="event">
                <option>Web Development</option>
                <option>AI Workshop</option>
                <option>Hackathon</option>
            </select>
        </label><br><br>
        <button type="submit">Register</button>
    </form>
    <p id="message"></p>
    <script>
        document.getElementById('registrationForm').addEventListener('submit', function (e) {
            e.preventDefault();
            const name = document.getElementById('name').value.trim();
            document.getElementById('message').textContent = 'Registration successful! Welcome ' + name + '.';
        });
    </script>
</body>
</html>
'@
    $manual = @'
EXPERIMENT 1 - MANUAL EXECUTION

1. Open PowerShell.
2. Run these commands to open the event registration form:

$desktop = [Environment]::GetFolderPath('Desktop')
Set-Location (Join-Path $desktop 'DevOps Lab\1. Event Registration Form')
Start-Process .\index.html

3. Enter your name and email, select an event, and click Register.
'@

    if (-not (Test-Path -LiteralPath $htmlPath)) { Write-TextFile $htmlPath $html }
    if (-not (Test-Path -LiteralPath $manualPath)) { Write-TextFile $manualPath $manual }
    if ($OpenBrowser) {
        Start-Process -FilePath $htmlPath
        Write-Host 'Experiment 1 created and opened in your default browser.' -ForegroundColor Green
    } else {
        Write-Host 'Experiment 1 files are ready.' -ForegroundColor Green
    }
}

function New-Experiment2 {
    New-Item -ItemType Directory -Path $Exp2 -Force | Out-Null
    $commands = @'
GIT AND GITHUB COMMANDS - EXPERIMENT 2

git --version
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
git init
git status
git add .
git add index.html
git commit -m "Initial commit"
git log --oneline
git branch
git switch -c feature
git switch main
git clone https://github.com/USERNAME/REPOSITORY.git
git remote -v
git remote add origin https://github.com/USERNAME/REPOSITORY.git
git branch -M main
git push -u origin main
git pull origin main
git fetch origin
git diff
git diff --staged
git restore FILE
git rm FILE

BASIC GITHUB WORKFLOW:
git init
git add .
git commit -m "First commit"
git branch -M main
git remote add origin REPOSITORY_URL
git push -u origin main

Authentication:
Use Git Credential Manager/browser sign-in when prompted.
Do not paste your GitHub password or personal access token into scripts or text files.
'@
    $manual = @'
EXPERIMENT 2 - MANUAL EXECUTION

1. Open PowerShell and check Git:
git --version

2. Open the Git command reference:
$desktop = [Environment]::GetFolderPath('Desktop')
Set-Location (Join-Path $desktop 'DevOps Lab\2. Git and GitHub Commands')
notepad .\git_commands.txt

3. Try the basic workflow inside a project folder:
git init
git add .
git commit -m "Initial commit"
git branch -M main
git remote add origin REPOSITORY_URL
git push -u origin main

Replace REPOSITORY_URL with your own GitHub repository URL.
'@
    Write-TextFile (Join-Path $Exp2 'git_commands.txt') $commands
    Write-TextFile (Join-Path $Exp2 'manual.txt') $manual
    Open-TextFile (Join-Path $Exp2 'git_commands.txt')
    Write-Host 'Experiment 2 command files created.' -ForegroundColor Green
}

function Start-Experiment3 {
    Ensure-Git
    New-Experiment1
    New-Item -ItemType Directory -Path $Exp3 -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $Exp1 'index.html') -Destination (Join-Path $Exp3 'index.html') -Force

    $manual = @'
EXPERIMENT 3 - MANUAL EXECUTION

1. Configure your Git identity:
git config --global user.name "Your Name"
git config --global user.email "you@example.com"

2. Clone your GitHub repository:
git clone REPOSITORY_URL
Set-Location .\REPOSITORY
(Replace REPOSITORY with the folder created by git clone.)

3. Copy Experiment 1 into the cloned repository:
$desktop = [Environment]::GetFolderPath('Desktop')
Copy-Item (Join-Path $desktop 'DevOps Lab\1. Event Registration Form\index.html') .\index.html -Force

4. Configure the commit identity in the cloned repository:
git config user.name "Your Name"
git config user.email "you@example.com"

5. Add, commit, and push:
git add .
git commit -m "Add event registration form"
git branch -M main
git push -u origin main

Replace REPOSITORY_URL with your HTTPS GitHub repository URL.
Git Credential Manager may open a browser for sign-in. Git author name/email are not GitHub login credentials.
'@
    Write-TextFile (Join-Path $Exp3 'manual.txt') $manual

    $repoUrl = Read-Host 'Enter your GitHub repository HTTPS URL'
    if ($repoUrl -notmatch '^https://github\.com/[^/]+/[^/]+(?:\.git)?/?$') {
        throw 'Enter a valid GitHub HTTPS URL, for example https://github.com/username/event-registration.git'
    }
    $gitName = Read-Host 'Enter Git username / commit author name'
    $gitEmail = Read-Host 'Enter Git email'
    if ([string]::IsNullOrWhiteSpace($gitName) -or [string]::IsNullOrWhiteSpace($gitEmail)) {
        throw 'Git author name and email are required.'
    }
    $branch = Read-Host 'Enter branch name [main]'
    if ([string]::IsNullOrWhiteSpace($branch)) { $branch = 'main' }

    & git check-ref-format --branch $branch *> $null
    if ($LASTEXITCODE -ne 0) { throw "Invalid Git branch name: $branch" }

    $work = Join-Path $env:TEMP ('DevOpsLabExp3_' + [guid]::NewGuid().ToString('N'))
    try {
        Write-Host "`nCloning GitHub repository..." -ForegroundColor Cyan
        Invoke-Git -GitArgs @('clone', $repoUrl, $work)
        Push-Location $work
        try {
            # Use the requested remote branch when it exists; otherwise create a new local branch.
            & git fetch origin $branch 2>$null
            & git show-ref --verify --quiet "refs/remotes/origin/$branch" 2>$null
            $hasRemoteBranch = ($LASTEXITCODE -eq 0)
            if ($hasRemoteBranch) {
                Invoke-Git -GitArgs @('checkout', '-B', $branch, "origin/$branch")
            } else {
                Invoke-Git -GitArgs @('checkout', '-B', $branch)
            }

            Invoke-Git -GitArgs @('config', 'user.name', $gitName)
            Invoke-Git -GitArgs @('config', 'user.email', $gitEmail)

            Get-ChildItem -LiteralPath $Exp3 -File | ForEach-Object {
                Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $work $_.Name) -Force
            }

            Invoke-Git -GitArgs @('add', '.')
            & git diff --cached --quiet
            $diffExit = $LASTEXITCODE
            if ($diffExit -eq 1) {
                Invoke-Git -GitArgs @('commit', '-m', 'Add event registration form')
            } elseif ($diffExit -gt 1) {
                throw 'Could not inspect staged Git changes.'
            } else {
                Write-Host 'No new changes to commit; pushing the selected branch.' -ForegroundColor Yellow
            }

            Invoke-Git -GitArgs @('push', '-u', 'origin', $branch)
        } finally {
            Pop-Location
        }
        Write-Host "Experiment 3 completed. Source code pushed to GitHub branch '$branch'." -ForegroundColor Green
    } finally {
        if (Test-Path -LiteralPath $work) {
            Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}


function New-Experiment5 {
    $repoUrl = 'https://github.com/SureshVadla0807/test1.git'
    New-Item -ItemType Directory -Path $Exp5 -Force | Out-Null

    # The Jenkinsfile is already committed in the public GitHub repository.
    # This experiment only creates the manual instructions and guides the user
    # through creating/configuring a Pipeline item in the Jenkins web interface.
    $manual = @'
EXPERIMENT 5 - JENKINS CI/CD INTEGRATION

GitHub repository:
https://github.com/SureshVadla0807/test1.git

Purpose:
Connect the existing public GitHub repository to Jenkins and run the Jenkinsfile already stored in the repository.

BEFORE YOU START:
- Jenkins must already be installed and running.
- The Git plugin must be available in Jenkins.
- The Jenkinsfile must already be committed in the ROOT of the repository on the main branch.
- The repository is public, so no GitHub credentials are needed for checkout.
- Do not create, copy, commit, or push another Jenkinsfile for this experiment. The file is already in GitHub.

PART A - CREATE A NEW JENKINS ITEM

1. Open the Jenkins dashboard in your browser. Common local address: http://localhost:8080
2. On the dashboard, click "New Item".
3. Enter the item name: test1
4. Select "Pipeline" (not Freestyle project).
5. Click "OK".

If an item named test1 already exists, do not create a duplicate. Open that existing item and click "Configure" instead.

PART B - CONNECT THE GITHUB REPOSITORY

1. In the job configuration page, scroll down to the "Pipeline" section.
2. For "Definition", choose "Pipeline script from SCM".
3. For "SCM", choose "Git".
4. In "Repository URL", paste:
   https://github.com/SureshVadla0807/test1.git
5. For "Credentials", choose "- None -" because the repository is public.
6. For "Branches to build" / "Branch Specifier", enter:
   */main
7. For "Script Path", enter:
   Jenkinsfile
8. Leave "Lightweight checkout" at its default setting unless your lab instructor specifies otherwise.
9. Click "Save".

PART C - RUN THE PIPELINE

1. Open the test1 job page.
2. Click "Build Now".
3. Wait for the build to finish.
4. Open the build number under "Build History".
5. Click "Console Output".
6. Verify that the pipeline stages run and the last line says:
   Finished: SUCCESS

WHAT TO RECORD FOR THE LAB:
- Screenshot of the Jenkins job configuration showing Pipeline script from SCM.
- Screenshot of the Build History with a successful build.
- Screenshot of Console Output showing the completed stages and Finished: SUCCESS.

TROUBLESHOOTING:
- If Jenkins cannot find the Jenkinsfile, confirm that the file is named exactly Jenkinsfile (capital J, no extension), is in the repository root, and is committed to main.
- If checkout works but a later stage fails, read the FIRST error in Console Output. The checkout step and the pipeline execution stages are separate.
- A message such as "No changes" by itself usually means no new repository commit was detected; it does not prove the build failed.
- Because the repository is public, do not add a GitHub password or personal access token just for cloning it.
'@

    Write-TextFile (Join-Path $Exp5 'manual.txt') $manual

    $clipboardCopied = $false
    try {
        Set-Clipboard -Value $repoUrl
        $clipboardCopied = $true
    } catch {
        $clipboardCopied = $false
    }

    Write-Title 'EXPERIMENT 5 - JENKINS PIPELINE SETUP'
    if ($clipboardCopied) {
        Write-Host 'GitHub repository URL copied to clipboard.' -ForegroundColor Green
    } else {
        Write-Host 'Clipboard copy was unavailable. Copy the repository URL shown below.' -ForegroundColor Yellow
    }
    Write-Host $repoUrl -ForegroundColor Cyan
    Write-Host ''
    Write-Host 'NEXT STEPS - FOLLOW THESE IN THE JENKINS BROWSER:' -ForegroundColor Yellow
    Write-Host '1. Open the Jenkins dashboard (commonly http://localhost:8080).'
    Write-Host '2. Click New Item.'
    Write-Host '3. Enter item name: test1'
    Write-Host '4. Select Pipeline, then click OK.'
    Write-Host '   If test1 already exists, open it and click Configure instead.'
    Write-Host '5. Scroll to Pipeline > Definition: Pipeline script from SCM.'
    Write-Host '6. SCM: Git | Repository URL: paste the copied URL | Credentials: - None -'
    Write-Host '7. Branch Specifier: */main | Script Path: Jenkinsfile'
    Write-Host '8. Click Save, open the test1 job, and click Build Now.'
    Write-Host '9. Open the build number > Console Output; check for Finished: SUCCESS.'
    Write-Host ''
    Write-Host 'The Jenkinsfile is already in GitHub. No git clone, file copy, commit, or push is required for this experiment.' -ForegroundColor Green
    Write-Host 'Manual instructions:' -ForegroundColor Green
    Write-Host (Join-Path $Exp5 'manual.txt')
    Open-TextFile (Join-Path $Exp5 'manual.txt')
}

function New-Experiment6 {
    New-Item -ItemType Directory -Path $Exp6 -Force | Out-Null
    $commands = @'
DOCKER COMMANDS - EXPERIMENT 6

docker --version
docker info
docker pull nginx
docker images
docker run hello-world
docker run -d -p 8000:80 --name mynginx nginx
docker ps
docker ps -a
docker stop mynginx
docker start mynginx
docker restart mynginx
docker logs mynginx
docker exec -it mynginx sh
docker inspect mynginx
docker rm -f mynginx
docker rmi nginx
docker volume ls
docker network ls
docker system prune

Open http://localhost:8000 to view the Nginx page.
Start Docker Desktop before executing Docker commands.
Note: Port 8000 is shared with Experiment 7. Stop/remove one container before using the same port for another container.
Use docker system prune carefully; it removes unused Docker resources.
'@
    $manual = @'
EXPERIMENT 6 - MANUAL EXECUTION

1. Start Docker Desktop.
2. Open PowerShell and verify Docker:
docker --version
docker info

3. Open the command list:
$desktop = [Environment]::GetFolderPath('Desktop')
Set-Location (Join-Path $desktop 'DevOps Lab\6. Docker Commands')
notepad .\docker_commands.txt

4. Try the Nginx container command:
docker run -d -p 8000:80 --name mynginx nginx
docker ps

5. Open http://localhost:8000
6. Stop and remove it:
docker rm -f mynginx
'@
    Write-TextFile (Join-Path $Exp6 'docker_commands.txt') $commands
    Write-TextFile (Join-Path $Exp6 'manual.txt') $manual
    Open-TextFile (Join-Path $Exp6 'docker_commands.txt')
    Write-Host 'Experiment 6 command files created.' -ForegroundColor Green
}

function Start-Experiment7 {
    Ensure-Experiment7Files -Overwrite
    Ensure-DockerApp -Rebuild
    Start-Process 'http://localhost:8000'
    Write-Host 'Experiment 7 completed. The containerized application is open in your browser.' -ForegroundColor Green
}

function New-Experiment11 {
    Ensure-SupportedNode
    New-Item -ItemType Directory -Path $Exp11 -Force | Out-Null

    $js = @'
const { Builder, Browser } = require('selenium-webdriver');
const { createInterface } = require('node:readline/promises');

(async function () {
    let driver;
    const rl = createInterface({ input: process.stdin, output: process.stdout });

    try {
        console.log('Starting Chrome with Selenium...');
        driver = await new Builder().forBrowser(Browser.CHROME).build();
        await driver.get('https://www.selenium.dev/');
        console.log('Chrome opened the official Selenium website.');
        await rl.question('Press Enter here to close Chrome...');
    } catch (error) {
        console.error('Selenium error:', error.message);
        process.exitCode = 1;
    } finally {
        rl.close();
        if (driver) await driver.quit();
    }
})();
'@
    $package = @'
{
  "name": "devops-lab-experiment-11",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "start": "node test.js"
  }
}
'@
    $manual = @'
EXPERIMENT 11 - MANUAL EXECUTION

Requirements:
- Node.js 22.23.4+, 24.22.1+, or 26.12.1+
- Google Chrome
- Internet connection for the initial Selenium / driver setup

Commands:
$desktop = [Environment]::GetFolderPath('Desktop')
Set-Location (Join-Path $desktop 'DevOps Lab\11. JavaScript Selenium Testing')
node --version
npm install selenium-webdriver
npm start

Selenium opens Chrome and navigates directly to https://www.selenium.dev/.
Press Enter in the PowerShell window to close Chrome.
The official Selenium website is used instead of Google search to avoid triggering Google's search CAPTCHA in this demo. CAPTCHA challenges cannot be bypassed by this script.
'@
    Write-TextFile (Join-Path $Exp11 'test.js') $js
    Write-TextFile (Join-Path $Exp11 'package.json') $package
    Write-TextFile (Join-Path $Exp11 'manual.txt') $manual

    Push-Location $Exp11
    try {
        Write-Host 'Installing Selenium WebDriver...' -ForegroundColor Cyan
        npm install selenium-webdriver
        if ($LASTEXITCODE -ne 0) { throw 'Selenium installation failed.' }
        Write-Host 'Launching Chrome...' -ForegroundColor Cyan
        npm start
        if ($LASTEXITCODE -ne 0) { throw 'Experiment 11 Selenium run failed.' }
    } finally {
        Pop-Location
    }
    Write-Host 'Experiment 11 completed.' -ForegroundColor Green
}

function Start-Experiment12 {
    Ensure-SupportedNode
    Ensure-Experiment7Files
    Ensure-DockerApp
    New-Item -ItemType Directory -Path $Exp12 -Force | Out-Null

    $testJs = @'
const { Builder, By, Browser, until } = require('selenium-webdriver');
const assert = require('node:assert/strict');

(async function runTests() {
    let driver;
    let passed = 0;

    async function test(name, action) {
        try {
            await action();
            passed++;
            console.log('PASS: ' + name);
        } catch (error) {
            console.log('FAIL: ' + name);
            throw error;
        }
    }

    try {
        driver = await new Builder().forBrowser(Browser.CHROME).build();
        await driver.get('http://localhost:8000');

        await test('TC01 - Application loads', async () => {
            assert.equal(await driver.getTitle(), 'Docker Application');
        });

        await test('TC02 - Docker application content', async () => {
            const heading = await driver.findElement(By.tagName('h2'));
            const message = await driver.findElement(By.xpath('//p[1]'));
            assert.equal(await heading.getText(), 'DevOps Lab - Docker Application');
            assert.equal(await message.getText(), 'Container is running successfully!');
        });

        await test('TC03 - Greeting with Test', async () => {
            const input = await driver.findElement(By.id('name'));
            const button = await driver.findElement(By.id('greetButton'));
            const result = await driver.findElement(By.id('greeting'));
            await input.sendKeys('Test');
            await button.click();
            await driver.wait(until.elementTextIs(result, 'Hello Test! Welcome to Docker.'), 5000);
            assert.equal(await result.getText(), 'Hello Test! Welcome to Docker.');
        });

        await test('TC04 - Empty input validation', async () => {
            const input = await driver.findElement(By.id('name'));
            const button = await driver.findElement(By.id('greetButton'));
            const result = await driver.findElement(By.id('greeting'));
            await input.clear();
            await button.click();
            await driver.wait(until.elementTextIs(result, 'Please enter your name.'), 5000);
            assert.equal(await result.getText(), 'Please enter your name.');
        });

        console.log(`\n${passed}/4 TESTS PASSED`);
        console.log('ALL TESTS COMPLETED SUCCESSFULLY!');
    } catch (error) {
        console.error('TEST EXECUTION FAILED:', error.message);
        process.exitCode = 1;
    } finally {
        if (driver) await driver.quit();
    }
})();
'@
    $package = @'
{
  "name": "devops-lab-experiment-12",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "test": "node test.js"
  }
}
'@
    $manual = @'
EXPERIMENT 12 - MANUAL EXECUTION

Requirements:
- Run Experiment 7 first, or ensure its Docker application is running.
- Docker Desktop and Docker Engine
- Node.js 22.23.4+, 24.22.1+, or 26.12.1+
- Google Chrome

Docker commands:
docker --version
docker info
docker ps -a

If the container does not exist, build and run it from the Experiment 7 folder:
$desktop = [Environment]::GetFolderPath('Desktop')
Set-Location (Join-Path $desktop 'DevOps Lab\7. Docker Containerized Application')
docker build -t devops-lab-app .
docker run -d -p 8000:80 --name devops-lab-app devops-lab-app

If it exists but is stopped:
docker start devops-lab-app

Open http://localhost:8000

Selenium commands:
$desktop = [Environment]::GetFolderPath('Desktop')
Set-Location (Join-Path $desktop 'DevOps Lab\12. Selenium Test Cases')
node --version
npm install selenium-webdriver
npm test

Test cases:
TC01 - Verify that the application loads.
TC02 - Verify the heading and container status message.
TC03 - Enter Test and verify: Hello Test! Welcome to Docker.
TC04 - Submit an empty name and verify: Please enter your name.

To stop the Docker application:
docker stop devops-lab-app
'@

    Write-TextFile (Join-Path $Exp12 'test.js') $testJs
    Write-TextFile (Join-Path $Exp12 'package.json') $package
    Write-TextFile (Join-Path $Exp12 'manual.txt') $manual

    Push-Location $Exp12
    try {
        Write-Host 'Installing Selenium WebDriver...' -ForegroundColor Cyan
        npm install selenium-webdriver
        if ($LASTEXITCODE -ne 0) { throw 'Selenium installation failed.' }
        Write-Host "`nRunning Selenium test cases against http://localhost:8000..." -ForegroundColor Cyan
        npm test
        if ($LASTEXITCODE -ne 0) { throw 'One or more Selenium test cases failed.' }
    } finally {
        Pop-Location
    }
    Write-Host 'Experiment 12 completed.' -ForegroundColor Green
}

Write-Host "`nDevOps Lab folder: $Root" -ForegroundColor Green

while ($true) {
    Write-Title 'DEVOPS LAB - EXPERIMENT MENU'
    Write-Host "Main folder: $Root"
    Write-Host '1. Event Registration Form'
    Write-Host '2. Git and GitHub Commands'
    Write-Host '3. GitHub Source Code Management (uses Experiment 1)'
    Write-Host '5. Jenkins CI/CD Integration (connect existing GitHub Jenkinsfile)'
    Write-Host '6. Docker Commands'
    Write-Host '7. Docker Containerized Application (port 8000)'
    Write-Host '11. JavaScript and Selenium - Open Selenium website'
    Write-Host '12. Selenium Test Cases for Experiment 7'
    Write-Host '0. Exit'

    $choice = Read-Host 'Select an experiment'
    try {
        switch ($choice) {
            '1'  { New-Experiment1 -OpenBrowser }
            '2'  { New-Experiment2 }
            '3'  { Start-Experiment3 }
            '5'  { New-Experiment5 }
            '6'  { New-Experiment6 }
            '7'  { Start-Experiment7 }
            '11' { New-Experiment11 }
            '12' { Start-Experiment12 }
            '0'  { Write-Host 'Exiting DevOps Lab.' -ForegroundColor Cyan; return }
            default { Write-Host 'Invalid choice. Select 1, 2, 3, 5, 6, 7, 11, 12, or 0.' -ForegroundColor Yellow }
        }
    } catch {
        Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
    if ($choice -ne '0') { Pause-Menu }
}
