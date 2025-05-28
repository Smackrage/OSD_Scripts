# Define Write-Log function for logging messages
function Write-Log {
    param (
        [string]$Message
    )
    Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
}

# Ensure TS Environment is Available
try {
    $TSEnv = New-Object -ComObject Microsoft.SMS.TSEnvironment
    Write-Log "Task Sequence environment detected."
} catch {
    Write-Log "ERROR: Task Sequence environment not found!"
    Exit 1
}

# Load required assemblies for Windows Forms and Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Create the form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Select Deployment Type"
$form.Size = New-Object System.Drawing.Size(320, 150)
$form.StartPosition = "CenterScreen"

# Create and configure the ComboBox (dropdown)
$comboBox = New-Object System.Windows.Forms.ComboBox
$comboBox.Location = New-Object System.Drawing.Point(10,10)
$comboBox.Size = New-Object System.Drawing.Size(280,20)
$comboBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList

# Define the options for the dropdown
$options = @("Option 1", "Option 2", "Option 3", "Option 4")
$comboBox.Items.AddRange($options)
$comboBox.SelectedIndex = 0  # Default selection is Option 1

# Add the ComboBox to the form
$form.Controls.Add($comboBox)

# Create and configure the OK button
$okButton = New-Object System.Windows.Forms.Button
$okButton.Location = New-Object System.Drawing.Point(10,40)
$okButton.Size = New-Object System.Drawing.Size(75,23)
$okButton.Text = "OK"
$okButton.Add_Click({
    # Store the user selection in the form's Tag property and close the form
    $form.Tag = $comboBox.SelectedItem
    $form.Close()
})
$form.Controls.Add($okButton)

# Create a label to display the countdown timer
$countdownLabel = New-Object System.Windows.Forms.Label
$countdownLabel.Location = New-Object System.Drawing.Point(100,45)
$countdownLabel.Size = New-Object System.Drawing.Size(200,20)
$remainingTime = 60
$countdownLabel.Text = "Time remaining: $remainingTime seconds"
$form.Controls.Add($countdownLabel)

# Create a timer with a 1-second interval
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000  # 1000 ms = 1 second
$timer.Add_Tick({
    $remainingTime--
    $countdownLabel.Text = "Time remaining: $remainingTime seconds"
    
    # If time runs out without a user selection, default to Option 1 and close the form
    if ($remainingTime -le 0 -and -not $form.Tag) {
        $comboBox.SelectedIndex = 0
        $form.Tag = $comboBox.SelectedItem
        $form.Close()
    }
})
$timer.Start()

# Show the form and wait for user input (or timeout)
[void] $form.ShowDialog()

# Retrieve the selected value
$deploymenttype = $form.Tag

# Log the selected deployment type
Write-Log "DeploymentType selected: $deploymenttype"

# Set the Task Sequence variable using the TS environment object
try {
    $TSEnv.Value("deploymenttype") = $deploymenttype
    Write-Log "Task Sequence variable 'deploymenttype' set to: $deploymenttype"
} catch {
    Write-Log "ERROR: Could not set Task Sequence variable 'deploymenttype'."
}
