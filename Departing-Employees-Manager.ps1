<<#
.SYNOPSIS
    مدير المغادرين الذكي
.DESCRIPTION
    أداة تفاعلية لمعالجة حسابات الموظفين المغادرين (تعطيل + نقل + توثيق).
    تتيح اختيار الموظفين من قائمة الأقسام أو من ملف CSV، مع إمكانية مراجعة القائمة
    قبل التنفيذ. تقوم بتعطيل الحساب، نقله إلى OU مخصصة (DisabledUsers)، وتسجيل تاريخ
    التعطيل والقسم السابق في وصف الحساب.
    الوظائف التي يقوم بها:
    1. اختيار المصدر: ملف CSV أو اختيار تفاعلي من Active Directory.
    2. عرض الحسابات المفعلة فقط (لأن المعطلين لا يحتاجون معالجة).
    3. إمكانية اختيار أكثر من مستخدم من أكثر من قسم.
    4. مراجعة القائمة وإمكانية حذف مستخدمين قبل التنفيذ.
    5. إنشاء OU "DisabledUsers" تلقائياً إذا لم تكن موجودة.
    6. تعطيل الحساب ونقله إلى OU المخصصة.
    7. تحديث وصف الحساب بتاريخ التعطيل والقسم السابق.
    8. عرض إحصائيات كاملة.
.NOTES
    المؤلف: عصام حميد حسين الحفاشي
    التاريخ: 2026-06-02
    الإصدار: 2.0
    يتطلب: Active Directory Module
#>

# ========== مدير المغادرين الذكي (تفاعلي + فحص + أسئلة) ==========
# ... (باقي الكود كما هو) ...
#>
# ========== مدير المغادرين الذكي (تفاعلي + فحص + أسئلة) ==========

Write-Host "`n========== مدير المغادرين الذكي ==========" -ForegroundColor Cyan

# 1. اختيار المصدر
Write-Host "`n[المصدر] من أين تريد اختيار الموظفين المغادرين؟" -ForegroundColor Yellow
Write-Host "  1 = من ملف CSV" -ForegroundColor White
Write-Host "  2 = من Active Directory (اختيار من الأقسام)" -ForegroundColor White
$SourceChoice = Read-Host "أدخل رقم الخيار (1 أو 2)"

$UsersToProcess = @()

# ========== المصدر 1: ملف CSV ==========
if ($SourceChoice -eq "1") {
    Add-Type -AssemblyName System.Windows.Forms
    $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog
    $FileBrowser.Title = "اختر ملف CSV الذي يحتوي على الموظفين المغادرين"
    $FileBrowser.Filter = "CSV files (*.csv)|*.csv"
    $FileBrowser.InitialDirectory = [Environment]::GetFolderPath('Desktop')
    
    if ($FileBrowser.ShowDialog() -eq "OK") {
        $CSVPath = $FileBrowser.FileName
        $UsersList = Import-Csv -Path $CSVPath
        foreach ($U in $UsersList) { $UsersToProcess += $U.SamAccountName }
        Write-Host "[تم] استيراد $($UsersToProcess.Count) مستخدم من الملف." -ForegroundColor Cyan
    } else { Write-Host "[إلغاء] لم تختر ملفاً." -ForegroundColor Yellow; exit }
}

# ========== المصدر 2: من AD مباشرة ==========
elseif ($SourceChoice -eq "2") {
    Write-Host "`n[بحث] جاري تحميل الأقسام من Active Directory..." -ForegroundColor Cyan
    
    # جلب المستخدمين المفعلين فقط (لأن المعطلين لا نحتاج معالجتهم)
    $AllUsers = Get-ADUser -Filter {Enabled -eq $true} -Properties DistinguishedName | Where-Object { $_.SamAccountName -notin @("Administrator","Guest","krbtgt") }
    
    if ($AllUsers.Count -eq 0) {
        Write-Host "[معلومات] لا توجد حسابات مفعلة." -ForegroundColor Green
        exit
    }
    
    # تجميع حسب القسم
    $Departments = @{}
    foreach ($U in $AllUsers) {
        if ($U.DistinguishedName -match "OU=([^,]+)") {
            $Dept = $Matches[1]
            if ($Dept -notin $Departments.Keys) { $Departments[$Dept] = @() }
            $Departments[$Dept] += $U
        }
    }
    
    Write-Host "[تم] العثور على $($Departments.Count) قسماً." -ForegroundColor Cyan
    
    # حلقة اختيار المستخدمين
    do {
        Clear-Host
        Write-Host "`n========== اختيار من الأقسام ==========" -ForegroundColor Cyan
        Write-Host "[المختارين حالياً: $($UsersToProcess.Count) مستخدم]" -ForegroundColor Yellow
        Write-Host "[الأقسام المتوفرة]" -ForegroundColor Yellow
        $DeptIndex = 1
        $DeptMap = @{}
        foreach ($Dept in $Departments.Keys) {
            $DeptMap["$DeptIndex"] = $Dept
            Write-Host "  $DeptIndex - $Dept ($($Departments[$Dept].Count) مستخدم مفعل)" -ForegroundColor White
            $DeptIndex++
        }
        
        $DeptChoice = Read-Host "`nاختر رقم القسم (أو 'done' للإنهاء)"
        if ($DeptChoice -eq "done") { break }
        if (-not $DeptMap.ContainsKey($DeptChoice)) { Write-Host "[خطأ] رقم غير صحيح." -ForegroundColor Red; Start-Sleep -Seconds 1; continue }
        
        $SelectedDept = $DeptMap[$DeptChoice]
        $DeptUsers = $Departments[$SelectedDept]
        
        # حلقة داخلية: اختيار أكثر من مستخدم
        do {
            Clear-Host
            Write-Host "`n========== قسم $SelectedDept ==========" -ForegroundColor Cyan
            $UserIndex = 1
            $UserMap = @{}
            foreach ($U in $DeptUsers) {
                $AlreadySelected = if ($UsersToProcess -contains $U.SamAccountName) { " (محدد)" } else { "" }
                Write-Host "  $UserIndex - $($U.Name) ($($U.SamAccountName))$AlreadySelected" -ForegroundColor White
                $UserMap["$UserIndex"] = $U.SamAccountName
                $UserIndex++
            }
            
            Write-Host "`n[اختيار]" -ForegroundColor Cyan
            Write-Host "  أدخل رقم | 'all' للجميع | 'done' للخروج"
            $UserChoice = Read-Host "`nاختيارك"
            
            if ($UserChoice -eq "done") { break }
            elseif ($UserChoice -eq "all") {
                foreach ($U in $DeptUsers) { if ($UsersToProcess -notcontains $U.SamAccountName) { $UsersToProcess += $U.SamAccountName } }
                Write-Host "[تم] إضافة الجميع." -ForegroundColor Green
            }
            elseif ($UserMap.ContainsKey($UserChoice)) {
                $Sel = $UserMap[$UserChoice]
                if ($UsersToProcess -notcontains $Sel) { $UsersToProcess += $Sel; Write-Host "[تم] إضافة $Sel." -ForegroundColor Green }
                else { Write-Host "[تنبيه] $Sel محدد." -ForegroundColor Yellow }
            }
            else { Write-Host "[خطأ] رقم غير صحيح." -ForegroundColor Red }
            Start-Sleep -Seconds 1
        } while ($true)
        
        Write-Host "`n[المختارين: $($UsersToProcess.Count)]" -ForegroundColor Cyan
        $UsersToProcess | ForEach-Object { Write-Host "  - $_" -ForegroundColor White }
        $AddMore = Read-Host "`nهل تريد إضافة من قسم آخر؟ (y/n)"
    } while ($AddMore -eq "y")
}

else { Write-Host "[خطأ] اختيار غير صحيح." -ForegroundColor Red; exit }

# 2. مراجعة القائمة (إمكانية الحذف)
do {
    Write-Host "`n========== مراجعة القائمة ==========" -ForegroundColor Cyan
    Write-Host "[القائمة الحالية: $($UsersToProcess.Count) مستخدم]" -ForegroundColor Yellow
    $Index = 1
    $EditMap = @{}
    foreach ($Sam in $UsersToProcess) {
        Write-Host "  $Index - $Sam" -ForegroundColor White
        $EditMap["$Index"] = $Sam
        $Index++
    }
    
    Write-Host "`n[تعديل] أدخل رقم للحذف | 'done' للمتابعة"
    $EditChoice = Read-Host "`nاختيارك"
    
    if ($EditChoice -eq "done") { break }
    elseif ($EditMap.ContainsKey($EditChoice)) {
        $ToRemove = $EditMap[$EditChoice]
        $UsersToProcess = $UsersToProcess | Where-Object { $_ -ne $ToRemove }
        Write-Host "[حذف] تم إزالة $ToRemove." -ForegroundColor Red
    }
    else { Write-Host "[خطأ] رقم غير صحيح." -ForegroundColor Red }
} while ($true)

# 3. تأكيد نهائي
Write-Host "`n[ملخص] سيتم معالجة $($UsersToProcess.Count) مستخدم (تعطيل + نقل)." -ForegroundColor Yellow
$UsersToProcess | ForEach-Object { Write-Host "  - $_" -ForegroundColor White }
$FinalConfirm = Read-Host "`nاكتب YES للتأكيد والتنفيذ"
if ($FinalConfirm -ne "YES") { Write-Host "[إلغاء] تم إلغاء العملية." -ForegroundColor Yellow; exit }

# 4. إنشاء OU DisabledUsers إذا لم تكن موجودة
$DisabledOU = "OU=DisabledUsers,DC=lab,DC=local"
$DisabledOUName = "DisabledUsers"
try {
    $null = Get-ADOrganizationalUnit -Identity $DisabledOU -ErrorAction Stop
    Write-Host "[موجودة] OU: $DisabledOUName" -ForegroundColor Yellow
} catch {
    New-ADOrganizationalUnit -Name $DisabledOUName -Path "DC=lab,DC=local" -ProtectedFromAccidentalDeletion $false
    Write-Host "[تم] إنشاء OU: $DisabledOUName" -ForegroundColor Green
}

# 5. تنفيذ العملية
$DisabledCount = 0; $MovedCount = 0; $NotFoundCount = 0; $AlreadyDisabledCount = 0
$DisableDate = Get-Date -Format "yyyy-MM-dd"

foreach ($Sam in $UsersToProcess) {
    Write-Host "`n[معالجة] $Sam ..." -ForegroundColor Yellow
    
    $ADUser = Get-ADUser -Filter "SamAccountName -eq '$Sam'" -Properties DisplayName, Enabled, DistinguishedName, Title, Department -ErrorAction SilentlyContinue
    
    if (!$ADUser) {
        Write-Host "  [خطأ] '$Sam' غير موجود." -ForegroundColor Red
        $NotFoundCount++
        continue
    }
    
    Write-Host "  الاسم: $($ADUser.DisplayName) | القسم: $($ADUser.Department) | المسمى: $($ADUser.Title)" -ForegroundColor White
    
    if (-not $ADUser.Enabled) {
        Write-Host "  [تخطي] معطل مسبقاً." -ForegroundColor Yellow
        $AlreadyDisabledCount++
    } else {
        try {
            Disable-ADAccount -Identity $Sam -ErrorAction Stop
            Write-Host "  [تم] تعطيل الحساب." -ForegroundColor Green
            $DisabledCount++
        } catch { Write-Host "  [خطأ] فشل التعطيل." -ForegroundColor Red; continue }
    }
    
    try {
        Move-ADObject -Identity $ADUser.DistinguishedName -TargetPath $DisabledOU -ErrorAction Stop
        Write-Host "  [تم] نقل إلى $DisabledOUName." -ForegroundColor Green
        $MovedCount++
    } catch { Write-Host "  [تحذير] فشل النقل." -ForegroundColor DarkYellow }
    
    try {
        Set-ADUser -Identity $Sam -Description "معطل منذ $DisableDate | القسم السابق: $($ADUser.Department)" -ErrorAction SilentlyContinue
        Write-Host "  [تم] تحديث الوصف." -ForegroundColor Green
    } catch {}
}

# 6. إحصائيات
Write-Host "`n========== إحصائيات ==========" -ForegroundColor Cyan
Write-Host "تم التعطيل     : $DisabledCount" -ForegroundColor Green
Write-Host "تم النقل       : $MovedCount" -ForegroundColor Green
Write-Host "معطلين مسبقاً  : $AlreadyDisabledCount" -ForegroundColor Yellow
Write-Host "غير موجودين   : $NotFoundCount" -ForegroundColor Red
Write-Host "==============================" -ForegroundColor Cyan
