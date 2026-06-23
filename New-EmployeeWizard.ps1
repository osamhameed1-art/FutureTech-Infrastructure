<#
.SYNOPSIS
    مهندس FutureTech الشامل (CSV + إضافة يدوية تفاعلية)
.DESCRIPTION
    هذا الكود يقوم ببناء البنية التحتية الكاملة لشركة FutureTech من الصفر.
    يدعم وضعين:
    1. الإضافة من ملف CSV (الوضع التلقائي).
    2. الإضافة اليدوية التفاعلية (اختيار قسم، إدخال بيانات الموظف، إمكانية إضافة أكثر من موظف).
    الوظائف التي يقوم بها:
    - إنشاء OUs تلقائياً (الشركة، HeadOffice، الأقسام).
    - إنشاء مجموعات الأمان (G_*).
    - إنشاء حسابات المستخدمين مع بياناتهم.
    - إنشاء مجلدات منزلية خاصة (HomeFolders).
    - إنشاء مجلدات الأقسام المشتركة (CompanyData) ومشاركتها.
    - تطبيق صلاحيات NTFS.
    - عرض تقرير نهائي مفصل.
.NOTES
    المؤلف: عصام حميد حسين الحفاشي 
    التاريخ: 2026-06-21
    الإصدار: 4.0 (مع الإضافة اليدوية التفاعلية)
    يتطلب: Active Directory Module، صلاحيات Domain Admin
#>

# ========== 1. طلب المعلومات الأساسية ==========
Write-Host "`n[الإعدادات] الرجاء إدخال المعلومات الأساسية:" -ForegroundColor Cyan
$DomainDNS = Read-Host "أدخل اسم النطاق (مثلاً FutureTech.com)"
$CompanyName = Read-Host "أدخل اسم الشركة (مثلاً FutureTech)"
$HomeRoot = Read-Host "أدخل مسار HomeFolders (مثلاً E:\HomeFolders)"
$CompanyRoot = Read-Host "أدخل مسار CompanyData (مثلاً E:\CompanyData)"

$SecurePass = ConvertTo-SecureString "P@ssw0rd" -AsPlainText -Force
$ForcePasswordChange = $true

$DomainDN = ($DomainDNS -split '\.' | ForEach-Object { "DC=$_" }) -join ','

# ========== 2. اختيار وضع الإضافة ==========
Write-Host "`n[وضع الإضافة] كيف تريد إضافة الموظفين؟" -ForegroundColor Cyan
Write-Host "  1 = من ملف CSV" -ForegroundColor White
Write-Host "  2 = إضافة يدوية (مستخدم واحد أو أكثر)" -ForegroundColor White
$Mode = Read-Host "أدخل رقم الخيار (1 أو 2)"

$ValidUsers = @()
$ManualUsers = @() # لتخزين المستخدمين المضافين يدوياً

if ($Mode -eq "1") {
    # ========== وضع CSV ==========
    Write-Host "`n[اختيار الملف] الرجاء اختيار ملف CSV..." -ForegroundColor Cyan
    Add-Type -AssemblyName System.Windows.Forms
    $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog
    $FileBrowser.Title = "اختر ملف CSV الذي يحتوي على الموظفين الجدد"
    $FileBrowser.Filter = "CSV files (*.csv)|*.csv"
    $FileBrowser.InitialDirectory = [Environment]::GetFolderPath('Desktop')

    if ($FileBrowser.ShowDialog() -eq "OK") {
        $CSVPath = $FileBrowser.FileName
        Write-Host "[تم] تم اختيار: $CSVPath" -ForegroundColor Cyan
    } else {
        Write-Host "[إلغاء] لم تختر ملفاً." -ForegroundColor Yellow
        exit
    }

    Write-Host "`n[فحص] جاري فحص ملف CSV..." -ForegroundColor Cyan
    $AllCSVUsers = Import-Csv -Path $CSVPath
    $TotalInFile = $AllCSVUsers.Count
    $CSVColumns = $AllCSVUsers[0].PSObject.Properties.Name

    Write-Host "[تم] العثور على $TotalInFile سجل." -ForegroundColor Cyan

    $MissingCritical = @()
    foreach ($User in $AllCSVUsers) {
        if ([string]::IsNullOrWhiteSpace($User.Name) -or 
            [string]::IsNullOrWhiteSpace($User.Sam) -or 
            [string]::IsNullOrWhiteSpace($User.UPN) -or 
            [string]::IsNullOrWhiteSpace($User.OU)) {
            $MissingCritical += $User
        } else {
            if ($User.OU -match "OU=([^,]+)") {
                $User | Add-Member -NotePropertyName "DepartmentName" -NotePropertyValue $Matches[1] -Force
            } else {
                $User | Add-Member -NotePropertyName "DepartmentName" -NotePropertyValue "General" -Force
            }
            $ValidUsers += $User
        }
    }

    Write-Host "  سجلات صالحة: $($ValidUsers.Count)" -ForegroundColor Green
    if ($MissingCritical.Count -gt 0) {
        Write-Host "  سجلات ناقصة: $($MissingCritical.Count)" -ForegroundColor Red
    }

    if ($ValidUsers.Count -eq 0) { Write-Host "[خطأ] لا توجد سجلات صالحة." -ForegroundColor Red; exit }

} elseif ($Mode -eq "2") {
    # ========== وضع الإضافة اليدوية ==========
    Write-Host "`n[إعداد] جاري تجهيز بيئة العمل للوضع اليدوي..." -ForegroundColor Cyan
    
    # التأكد من وجود OU الشركة و HeadOffice (إذا لم تكن موجودة، ننشئها)
    $CompanyOUPath = "OU=$CompanyName,$DomainDN"
    try { Get-ADOrganizationalUnit -Identity $CompanyOUPath -ErrorAction Stop | Out-Null }
    catch { New-ADOrganizationalUnit -Name $CompanyName -Path $DomainDN -ProtectedFromAccidentalDeletion $false }
    
    $HeadOfficePath = "OU=HeadOffice,$CompanyOUPath"
    try { Get-ADOrganizationalUnit -Identity $HeadOfficePath -ErrorAction Stop | Out-Null }
    catch { New-ADOrganizationalUnit -Name "HeadOffice" -Path $CompanyOUPath -ProtectedFromAccidentalDeletion $false }

    # جلب الأقسام الموجودة
    $ExistingDepts = Get-ADOrganizationalUnit -Filter * -SearchBase $HeadOfficePath -SearchScope OneLevel | Select-Object -ExpandProperty Name
    
    if ($ExistingDepts.Count -eq 0) {
        Write-Host "[خطأ] لا توجد أقسام حالياً. الرجاء تشغيل وضع CSV أولاً لإنشاء الأقسام." -ForegroundColor Red
        exit
    }

    # حلقة الإضافة اليدوية
    do {
        Clear-Host
        Write-Host "`n========== إضافة موظف يدوياً ==========" -ForegroundColor Cyan
        Write-Host "[الأقسام المتوفرة]" -ForegroundColor Yellow
        $DeptIndex = 1
        $DeptMap = @{}
        foreach ($Dept in $ExistingDepts) {
            $DeptMap["$DeptIndex"] = $Dept
            Write-Host "  $DeptIndex - $Dept" -ForegroundColor White
            $DeptIndex++
        }

        $DeptChoice = Read-Host "`nاختر رقم القسم (أو 'done' للإنهاء)"
        if ($DeptChoice -eq "done") { break }
        if (-not $DeptMap.ContainsKey($DeptChoice)) { Write-Host "[خطأ] رقم غير صحيح." -ForegroundColor Red; Start-Sleep -Seconds 1; continue }

        $SelectedDept = $DeptMap[$DeptChoice]
        
        # إدخال بيانات الموظف
        Write-Host "`n[بيانات الموظف]" -ForegroundColor Yellow
        $FullName = Read-Host "الاسم الكامل (مثلاً Ahmed Samir)"
        $Sam = Read-Host "اسم الدخول (SamAccountName) (مثلاً a.samir)"
        $UPN = Read-Host "البريد الإلكتروني (UserPrincipalName) (مثلاً a.samir@$DomainDNS)"
        $Title = Read-Host "المسمى الوظيفي (اختياري)"
        $Phone = Read-Host "رقم الهاتف (اختياري)"
        $City = Read-Host "المدينة (اختياري)"

        # تخزين بيانات المستخدم في كائن مخصص
        $ManualUser = [PSCustomObject]@{
            Name = $FullName
            Sam = $Sam
            UPN = $UPN
            DepartmentName = $SelectedDept
            Group = "G_$SelectedDept"
            Title = $Title
            Phone = $Phone
            City = $City
        }
        $ManualUsers += $ManualUser
        Write-Host "[تمت الإضافة مؤقتاً] $FullName -> $SelectedDept" -ForegroundColor Green

    } while ($true)

    if ($ManualUsers.Count -eq 0) { Write-Host "[إلغاء] لم تتم إضافة أي مستخدم." -ForegroundColor Yellow; exit }
    
    $ValidUsers = $ManualUsers
    $TotalInFile = $ManualUsers.Count
    $CSVColumns = @('Name','Sam','UPN','DepartmentName','Group','Title','Phone','City') # أعمدة افتراضية للوضع اليدوي

} else {
    Write-Host "[خطأ] اختيار غير صحيح." -ForegroundColor Red
    exit
}

# ========== 3. تأكيد قبل البدء ==========
$Confirm = Read-Host "`nهل تريد متابعة إنشاء $($ValidUsers.Count) مستخدم؟ (y/n)"
if ($Confirm -ne "y") { Write-Host "[إلغاء] تم إلغاء العملية." -ForegroundColor Yellow; exit }

# ========== 4. بناء OU تلقائياً (للوضعين) ==========
Write-Host "`n[تجهيز] جاري بناء الوحدات التنظيمية..." -ForegroundColor Cyan

$CreatedDepts = @()
$CreatedGroups = @()

$CompanyOUPath = "OU=$CompanyName,$DomainDN"
try { Get-ADOrganizationalUnit -Identity $CompanyOUPath -ErrorAction Stop | Out-Null }
catch { New-ADOrganizationalUnit -Name $CompanyName -Path $DomainDN -ProtectedFromAccidentalDeletion $false }

$HeadOfficePath = "OU=HeadOffice,$CompanyOUPath"
try { Get-ADOrganizationalUnit -Identity $HeadOfficePath -ErrorAction Stop | Out-Null }
catch { New-ADOrganizationalUnit -Name "HeadOffice" -Path $CompanyOUPath -ProtectedFromAccidentalDeletion $false }

$UniqueDepts = $ValidUsers | Select-Object -ExpandProperty DepartmentName -Unique

foreach ($Dept in $UniqueDepts) {
    $DeptPath = "OU=$Dept,$HeadOfficePath"
    try {
        Get-ADOrganizationalUnit -Identity $DeptPath -ErrorAction Stop | Out-Null
        Write-Host "[موجود] OU: $Dept" -ForegroundColor Yellow
    } catch {
        New-ADOrganizationalUnit -Name $Dept -Path $HeadOfficePath -ProtectedFromAccidentalDeletion $false
        Write-Host "[تم] إنشاء OU: $Dept" -ForegroundColor Green
        $CreatedDepts += $Dept
    }
    
    $GroupName = "G_$Dept"
    if (!(Get-ADGroup -Filter "Name -eq '$GroupName'" -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name $GroupName -GroupScope Global -GroupCategory Security -Path $DeptPath
        Write-Host "[تم] إنشاء مجموعة: $GroupName" -ForegroundColor Green
        $CreatedGroups += $GroupName
    }
}

# ========== 5. إنشاء المستخدمين والمجلدات المنزلية ==========
Write-Host "`n[تنفيذ] جاري إنشاء $($ValidUsers.Count) مستخدم..." -ForegroundColor Cyan

$PropertyMap = @{
    'Name'='Name'; 'Sam'='SamAccountName'; 'UPN'='UserPrincipalName'; 'OU'='Path'
    'Phone'='OfficePhone'; 'Mobile'='MobilePhone'; 'Title'='Title'
    'City'='City'; 'Department'='Department'; 'Manager'='Manager'
}

if (!(Test-Path -Path $HomeRoot)) { New-Item -Path $HomeRoot -ItemType Directory -Force | Out-Null }

$CreatedUsers = 0; $SkippedUsers = 0; $FailedUsers = 0
$CreatedFolders = 0; $SkippedFolders = 0

foreach ($User in $ValidUsers) {
    $FullName = $User.Name
    $SamAccountName = $User.Sam
    $UPN = $User.UPN
    $Department = $User.DepartmentName
    $GroupName = $User.Group
    
    $OUPath = "OU=$Department,$HeadOfficePath"
    
    $ADUserParams = @{
        Name = $FullName
        GivenName = ($FullName -split ' ')[0]
        Surname = if (($FullName -split ' ').Count -gt 1) { ($FullName -split ' ')[1] } else { "" }
        SamAccountName = $SamAccountName
        UserPrincipalName = $UPN
        Path = $OUPath
        AccountPassword = $SecurePass
        Enabled = $true
        PasswordNeverExpires = $false
        ErrorAction = 'Stop'
    }
    
    # إضافة البيانات الاختيارية (للوضعين)
    foreach ($Column in $CSVColumns) {
        if ($Column -in @('Name','Sam','UPN','OU','Group','DepartmentName')) { continue }
        $Value = $User.$Column
        if ([string]::IsNullOrWhiteSpace($Value)) { continue }
        if ($PropertyMap.ContainsKey($Column)) { $ADUserParams[$PropertyMap[$Column]] = $Value }
    }
    
    $Exists = Get-ADUser -Filter "UserPrincipalName -eq '$UPN'" -ErrorAction SilentlyContinue
    
    if ($Exists) {
        Write-Host "[تخطي] $FullName موجود" -ForegroundColor Yellow
        $SkippedUsers++
    } else {
        try {
            New-ADUser @ADUserParams
            if ($ForcePasswordChange) { Set-ADUser -Identity $SamAccountName -ChangePasswordAtLogon $true }
            Write-Host "[تم] إنشاء: $FullName" -ForegroundColor Green
            $CreatedUsers++
            if ($GroupName) { Add-ADGroupMember -Identity $GroupName -Members $SamAccountName -ErrorAction SilentlyContinue }
        } catch {
            Write-Host "[خطأ] فشل $FullName : $_" -ForegroundColor Red
            $FailedUsers++
            continue
        }
    }
    
    $DeptFolder = Join-Path -Path $HomeRoot -ChildPath $Department
    $UserFolder = Join-Path -Path $DeptFolder -ChildPath $SamAccountName
    
    if (!(Test-Path -Path $DeptFolder)) { New-Item -Path $DeptFolder -ItemType Directory -Force | Out-Null }
    
    if (Test-Path -Path $UserFolder) {
        Write-Host "[تخطي] المجلد موجود: $SamAccountName" -ForegroundColor Yellow
        $SkippedFolders++
    } else {
        try {
            New-Item -Path $UserFolder -ItemType Directory -Force | Out-Null
            $Acl = Get-Acl $UserFolder; $Acl.SetAccessRuleProtection($true, $false)
            $Acl.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("SYSTEM","FullControl","ContainerInherit,ObjectInherit","None","Allow")))
            $Acl.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("Administrators","FullControl","ContainerInherit,ObjectInherit","None","Allow")))
            $Acl.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("$DomainDNS\$SamAccountName","FullControl","ContainerInherit,ObjectInherit","None","Allow")))
            Set-Acl -Path $UserFolder -AclObject $Acl
            Write-Host "[مجلد] تم إنشاء: $SamAccountName -> $Department (خاص)" -ForegroundColor Green
            $CreatedFolders++
        } catch { Write-Host "[خطأ] فشل مجلد $SamAccountName : $_" -ForegroundColor Red }
    }
}

# ========== 6. إنشاء مجلدات CompanyData ومشاركتها ==========
Write-Host "`n[CompanyData] جاري إنشاء مجلدات الأقسام المشتركة..." -ForegroundColor Cyan

if (!(Test-Path -Path $CompanyRoot)) { New-Item -Path $CompanyRoot -ItemType Directory -Force | Out-Null }

$CompanyFoldersCreated = 0
$CompanySharesCreated = 0

foreach ($Dept in $UniqueDepts) {
    $CompFolder = Join-Path -Path $CompanyRoot -ChildPath $Dept
    $ShareName = $Dept + "Data"
    
    if (!(Test-Path -Path $CompFolder)) {
        New-Item -Path $CompFolder -ItemType Directory -Force | Out-Null
        Write-Host "[Company] تم إنشاء مجلد: $Dept" -ForegroundColor Green
        $CompanyFoldersCreated++
    }
    
    if (!(Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue)) {
        New-SmbShare -Name $ShareName -Path $CompFolder -FullAccess "Everyone"
        Write-Host "[مشاركة] تم إنشاء: $ShareName" -ForegroundColor Green
        $CompanySharesCreated++
    }
    
    $Acl = Get-Acl $CompFolder
    $Acl.SetAccessRuleProtection($true, $false)
    $Acl.Access | Where-Object { $_.AccessControlType -eq "Deny" } | ForEach-Object { $Acl.RemoveAccessRule($_) }
    
    $SystemRule = New-Object System.Security.AccessControl.FileSystemAccessRule("SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $AdminRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $GroupRule = New-Object System.Security.AccessControl.FileSystemAccessRule("$DomainDNS\G_$Dept", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
    
    $Acl.SetAccessRule($SystemRule)
    $Acl.SetAccessRule($AdminRule)
    $Acl.SetAccessRule($GroupRule)
    Set-Acl -Path $CompFolder -AclObject $Acl
    Write-Host "[NTFS] تم تأمين: $Dept -> G_$Dept" -ForegroundColor Magenta
}

# ========== 7. تقرير نهائي ==========
Write-Host "`n========== تقرير نهائي ==========" -ForegroundColor Cyan
Write-Host "الشركة: $CompanyName" -ForegroundColor White
Write-Host "النطاق: $DomainDNS" -ForegroundColor White
Write-Host "الأقسام المنشأة: $($CreatedDepts -join ', ')" -ForegroundColor Green
Write-Host "المجموعات المنشأة: $($CreatedGroups -join ', ')" -ForegroundColor Green
Write-Host "----------------------------------------" -ForegroundColor Gray
Write-Host "[HomeFolders]" -ForegroundColor Yellow
Write-Host "  تم إنشاء المستخدمين: $CreatedUsers" -ForegroundColor Green
Write-Host "  تم تخطي المستخدمين: $SkippedUsers" -ForegroundColor Yellow
Write-Host "  فشل إنشاء المستخدمين: $FailedUsers" -ForegroundColor Red
Write-Host "  تم إنشاء المجلدات: $CreatedFolders" -ForegroundColor Green
Write-Host "  تم تخطي المجلدات: $SkippedFolders" -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Gray
Write-Host "[CompanyData]" -ForegroundColor Yellow
Write-Host "  تم إنشاء المجلدات: $CompanyFoldersCreated" -ForegroundColor Green
Write-Host "  تم إنشاء المشاركات: $CompanySharesCreated" -ForegroundColor Green
Write-Host "====================================" -ForegroundColor Cyan
