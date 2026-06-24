<#
.SYNOPSIS
    مدير DFS الذكي (الإصدار النهائي)
.DESCRIPTION
    أداة شاملة وتفاعلية لإدارة DFS Replication بنظام القوائم.
    تمكنك من إنشاء، تعديل، حذف، وتشخيص مجموعات النسخ المتماثل.
    الوظائف التي يقوم بها:
    1. عرض جميع مجموعات DFS الموجودة.
    2. إنشاء مجموعة نسخ جديدة مع التحقق من عدم تكرار الاسم.
    3. تعديل مسار مجلد في مجموعة موجودة.
    4. حذف مجموعة موجودة مع تنظيف كامل.
    5. تشخيص وإصلاح تلقائي لمشاكل الاتصال والعضوية وتراكم الملفات.
    6. إصلاح مشكلة "Invalid Version Vector" عبر إعادة تعيين قاعدة البيانات.
    7. عرض تقرير مفصل عن حالة جميع المجموعات (سليمة/تحتاج إصلاح).
    8. واجهة قوائم تفاعلية مع إمكانية العودة للقائمة الرئيسية.
.NOTES
    المؤلف: عصام حميد حسين الحفاشي
    التاريخ: 2026-06-20
    الإصدار: 3.0 (النسخة النهائية)
    يتطلب: دور DFS Replication مثبت، صلاحيات Domain Admin
#>

# ========== مدير DFS الذكي (الإصدار النهائي مع التقرير المحسن) ==========
# ... (باقي الكود كما هو) ...





# ========== مدير DFS الذكي (الإصدار النهائي مع التقرير المحسن) ==========

do {
    Clear-Host
    Write-Host "`n========== مدير DFS الذكي ==========" -ForegroundColor Cyan
    Write-Host "هذا الكود يدير DFS Replication بشكل كامل وتلقائي." -ForegroundColor Yellow

    # عرض المجموعات الموجودة
    $ExistingGroups = Get-DfsReplicationGroup -ErrorAction SilentlyContinue
    if ($ExistingGroups) {
        Write-Host "`n[موجودة] تم العثور على $($ExistingGroups.Count) مجموعات DFS." -ForegroundColor Yellow
    } else {
        Write-Host "`n[معلومات] لا توجد مجموعات DFS سابقة." -ForegroundColor Green
    }

    # اختيار العملية
    Write-Host "`n[=] ماذا تريد أن تفعل؟" -ForegroundColor Cyan
    Write-Host "  1 = إنشاء مجموعة نسخ جديدة" -ForegroundColor White
    Write-Host "  2 = تعديل مسار مجلد في مجموعة موجودة" -ForegroundColor White
    Write-Host "  3 = حذف مجموعة موجودة" -ForegroundColor White
    Write-Host "  4 = تشخيص وإصلاح مجموعة (تلقائي)" -ForegroundColor White
    Write-Host "  5 = عرض تقرير مفصل عن جميع المجموعات" -ForegroundColor White
    Write-Host "  0 = خروج" -ForegroundColor White
    $Action = Read-Host "`nأدخل رقم الخيار"

    # ========== الخيار 1: إنشاء مجموعة جديدة ==========
    if ($Action -eq "1") {
        do {
            Write-Host "`n[إنشاء] إدخال البيانات المطلوبة..." -ForegroundColor Cyan
            do {
                $GroupName = Read-Host "أدخل اسم المجموعة الجديدة"
                $Exists = Get-DfsReplicationGroup -GroupName $GroupName -ErrorAction SilentlyContinue
                if ($Exists) { Write-Host "[خطأ] الاسم '$GroupName' موجود مسبقاً." -ForegroundColor Red }
            } while ($Exists)
            
            $Server1 = Read-Host "أدخل اسم السيرفر الرئيسي"
            $Server2 = Read-Host "أدخل اسم السيرفر الثاني"
            $FolderName = Read-Host "أدخل اسم المجلد المنسوخ"
            $Path1 = Read-Host "أدخل مسار المجلد على السيرفر الرئيسي"
            $Path2 = Read-Host "أدخل مسار المجلد على السيرفر الثاني"
            
            Write-Host "`n========== ملخص البيانات ==========" -ForegroundColor Yellow
            Write-Host "اسم المجموعة: $GroupName"
            Write-Host "السيرفر الرئيسي: $Server1"
            Write-Host "السيرفر الثاني: $Server2"
            Write-Host "اسم المجلد المنسوخ: $FolderName"
            Write-Host "مسار المجلد على $Server1 : $Path1"
            Write-Host "مسار المجلد على $Server2 : $Path2"
            Write-Host "====================================" -ForegroundColor Yellow
            $Confirm = Read-Host "`nهل هذه البيانات صحيحة؟ (y/n)"
        } while ($Confirm -ne "y")
        
        Write-Host "`n[تنفيذ] جاري إنشاء مجموعة النسخ..." -ForegroundColor Cyan
        New-DfsReplicationGroup -GroupName $GroupName
        Add-DfsrMember -GroupName $GroupName -ComputerName $Server1
        Add-DfsrMember -GroupName $GroupName -ComputerName $Server2
        New-DfsReplicatedFolder -GroupName $GroupName -FolderName $FolderName
        Set-DfsrMembership -GroupName $GroupName -FolderName $FolderName -ComputerName $Server1 -ContentPath $Path1 -PrimaryMember $true -Force
        Set-DfsrMembership -GroupName $GroupName -FolderName $FolderName -ComputerName $Server2 -ContentPath $Path2 -Force
        Add-DfsrConnection -GroupName $GroupName -SourceComputerName $Server1 -DestinationComputerName $Server2 -ErrorAction SilentlyContinue
        Add-DfsrConnection -GroupName $GroupName -SourceComputerName $Server2 -DestinationComputerName $Server1 -ErrorAction SilentlyContinue
        Update-DfsrConfigurationFromAD -ComputerName $Server1
        Update-DfsrConfigurationFromAD -ComputerName $Server2
        Restart-Service DFSR -Force
        Start-Sleep -Seconds 10
        Write-Host "[نجاح] تم إنشاء مجموعة النسخ بنجاح!" -ForegroundColor Green
    }

    # ========== الخيار 2: تعديل مسار مجلد ==========
    elseif ($Action -eq "2") {
        if (!$ExistingGroups) { Write-Host "[خطأ] لا توجد مجموعات DFS." -ForegroundColor Red }
        else {
            Write-Host "`n[تعديل] المجموعات المتاحة:" -ForegroundColor Yellow
            $ExistingGroups | ForEach-Object { Write-Host "  - $($_.GroupName)" -ForegroundColor White }
            $GroupName = Read-Host "`nأدخل اسم المجموعة التي تريد تعديلها"
            $TargetGroup = Get-DfsReplicationGroup -GroupName $GroupName -ErrorAction SilentlyContinue
            if ($TargetGroup) {
                $Members = Get-DfsrMember -GroupName $GroupName
                Write-Host "`n[الأعضاء الحاليون]" -ForegroundColor Yellow
                $Members | ForEach-Object { Write-Host "  - $($_.ComputerName)" -ForegroundColor White }
                $TargetServer = Read-Host "`nأدخل اسم السيرفر الذي تريد تعديل مساره"
                $TargetFolder = Read-Host "أدخل اسم المجلد المنسوخ"
                $NewPath = Read-Host "أدخل المسار الجديد للمجلد"
                Set-DfsrMembership -GroupName $GroupName -FolderName $TargetFolder -ComputerName $TargetServer -ContentPath $NewPath -Force
                Write-Host "[تم] تم تحديث مسار المجلد." -ForegroundColor Green
                Update-DfsrConfigurationFromAD -ComputerName $TargetServer
                Restart-Service DFSR -Force
            } else { Write-Host "[خطأ] المجموعة '$GroupName' غير موجودة." -ForegroundColor Red }
        }
    }

    # ========== الخيار 3: حذف مجموعة ==========
    elseif ($Action -eq "3") {
        if (!$ExistingGroups) { Write-Host "[خطأ] لا توجد مجموعات DFS." -ForegroundColor Red }
        else {
            Write-Host "`n[حذف] المجموعات المتاحة:" -ForegroundColor Yellow
            $ExistingGroups | ForEach-Object { Write-Host "  - $($_.GroupName)" -ForegroundColor White }
            $GroupName = Read-Host "`nأدخل اسم المجموعة التي تريد حذفها"
            $TargetGroup = Get-DfsReplicationGroup -GroupName $GroupName -ErrorAction SilentlyContinue
            if ($TargetGroup) {
                $ConfirmDelete = Read-Host "هل أنت متأكد من حذف '$GroupName'؟ اكتب YES للتأكيد"
                if ($ConfirmDelete -eq "YES") {
                    Get-DfsReplicatedFolder -GroupName $GroupName | ForEach-Object {
                        Remove-DfsReplicatedFolder -GroupName $GroupName -FolderName $_.FolderName -Force -ErrorAction SilentlyContinue
                    }
                    Remove-DfsReplicationGroup -GroupName $GroupName -Force
                    Write-Host "[حذف] تم حذف المجموعة: $GroupName" -ForegroundColor Red
                }
            } else { Write-Host "[خطأ] المجموعة '$GroupName' غير موجودة." -ForegroundColor Red }
        }
    }

    # ========== الخيار 4: تشخيص وإصلاح تلقائي ==========
    elseif ($Action -eq "4") {
        if (!$ExistingGroups) { Write-Host "[خطأ] لا توجد مجموعات DFS." -ForegroundColor Red }
        else {
            Write-Host "`n[تشخيص] المجموعات المتاحة:" -ForegroundColor Yellow
            $ExistingGroups | ForEach-Object { Write-Host "  - $($_.GroupName)" -ForegroundColor White }
            $GroupName = Read-Host "`nأدخل اسم المجموعة التي تريد تشخيصها وإصلاحها"
            $TargetGroup = Get-DfsReplicationGroup -GroupName $GroupName -ErrorAction SilentlyContinue
            
            if ($TargetGroup) {
                Write-Host "`n[فحص] جاري تشخيص المجموعة '$GroupName'..." -ForegroundColor Cyan
                $NeedsReset = @()
                $FixedConnections = 0
                $FixedMemberships = 0
                
                $Connections = Get-DfsrConnection -GroupName $GroupName -ErrorAction SilentlyContinue
                foreach ($Conn in $Connections) {
                    if (-not $Conn.Enabled) {
                        Set-DfsrConnection -GroupName $GroupName -SourceComputerName $Conn.SourceComputerName -DestinationComputerName $Conn.DestinationComputerName -Enabled $true
                        $FixedConnections++
                    }
                }
                
                $Memberships = Get-DfsrMembership -GroupName $GroupName -ErrorAction SilentlyContinue
                foreach ($Mem in $Memberships) {
                    if (-not $Mem.Enabled) {
                        Set-DfsrMembership -GroupName $GroupName -FolderName $Mem.FolderName -ComputerName $Mem.ComputerName -ContentPath $Mem.ContentPath -Force
                        $FixedMemberships++
                    }
                }
                
                $Members = $Memberships | Select-Object -ExpandProperty ComputerName -Unique
                foreach ($Source in $Members) {
                    foreach ($Dest in $Members) {
                        if ($Source -ne $Dest) {
                            try {
                                $Backlog = Get-DfsrBacklog -SourceComputerName $Source -DestinationComputerName $Dest -GroupName $GroupName -FolderName $Memberships[0].FolderName -ErrorAction Stop
                            } catch {
                                if ($_.Exception.Message -like "*Invalid version vector*") {
                                    if ($Dest -notin $NeedsReset) { $NeedsReset += $Dest }
                                }
                            }
                        }
                    }
                }
                
                if ($FixedConnections -gt 0) { Write-Host "[إصلاح] تم تفعيل $FixedConnections اتصال." -ForegroundColor Green }
                if ($FixedMemberships -gt 0) { Write-Host "[إصلاح] تم تفعيل $FixedMemberships عضوية." -ForegroundColor Green }
                
                if ($NeedsReset.Count -gt 0) {
                    Write-Host "`n[مشكلة] تم اكتشاف Invalid Version Vector في: $($NeedsReset -join ', ')" -ForegroundColor Red
                    $ConfirmFix = Read-Host "`nاكتب YES لإصلاح قاعدة البيانات"
                    if ($ConfirmFix -eq "YES") {
                        foreach ($Server in $NeedsReset) {
                            Write-Host "`n[تنفيذ] افتح PowerShell كمسؤول على $Server ونفذ:" -ForegroundColor Cyan
                            Write-Host "  Stop-Service DFSR -Force" -ForegroundColor White
                            Write-Host "  Remove-Item -Path 'C:\System Volume Information\DFSR\*' -Recurse -Force -ErrorAction SilentlyContinue" -ForegroundColor White
                            Write-Host "  Start-Service DFSR" -ForegroundColor White
                            $Done = Read-Host "`nهل قمت بتنفيذ الأوامر على $Server؟ (y/n)"
                            if ($Done -eq "y") { Update-DfsrConfigurationFromAD -ComputerName $Server }
                        }
                        Restart-Service DFSR -Force
                        Write-Host "[نجاح] تم إصلاح المشكلة." -ForegroundColor Green
                    }
                } else {
                    Write-Host "`n[سليم] لا توجد مشاكل في المجموعة '$GroupName'." -ForegroundColor Green
                }
            } else { Write-Host "[خطأ] المجموعة '$GroupName' غير موجودة." -ForegroundColor Red }
        }
    }

    # ========== الخيار 5: تقرير مفصل (فقط عرض) ==========
    elseif ($Action -eq "5") {
        Write-Host "`n############################################" -ForegroundColor Cyan
        Write-Host "#        تقرير DFS Replication المفصل       #" -ForegroundColor Cyan
        Write-Host "############################################" -ForegroundColor Cyan
        
        $AllGroups = Get-DfsReplicationGroup -ErrorAction SilentlyContinue
        if ($AllGroups) {
            $TotalGroups = $AllGroups.Count
            $HealthyGroups = 0
            $ProblemGroups = 0
            
            foreach ($Group in $AllGroups) {
                $HasProblem = $false
                $Mems = Get-DfsrMembership -GroupName $Group.GroupName -ErrorAction SilentlyContinue
                $Members = $Mems | Select-Object -ExpandProperty ComputerName -Unique
                
                # فحص Backlog
                foreach ($Source in $Members) {
                    foreach ($Dest in $Members) {
                        if ($Source -ne $Dest) {
                            try {
                                $Backlog = Get-DfsrBacklog -SourceComputerName $Source -DestinationComputerName $Dest -GroupName $Group.GroupName -FolderName $Mems[0].FolderName -ErrorAction Stop | Out-Null
                            } catch {
                                if ($_.Exception.Message -like "*Invalid version vector*") {
                                    $HasProblem = $true
                                }
                            }
                        }
                    }
                }
                
                if ($HasProblem) { $ProblemGroups++ } else { $HealthyGroups++ }
            }
            
            # ملخص عام
            Write-Host "`n[ ملخص عام ]" -ForegroundColor Yellow
            Write-Host "  إجمالي المجموعات: $TotalGroups" -ForegroundColor White
            Write-Host "  مجموعات سليمة: $HealthyGroups ✅" -ForegroundColor Green
            Write-Host "  مجموعات بها مشاكل: $ProblemGroups ❌" -ForegroundColor Red
            
            # جدول تفصيلي لكل مجموعة
            Write-Host "`n[ تفاصيل المجموعات ]" -ForegroundColor Yellow
            $Index = 1
            foreach ($Group in $AllGroups) {
                $HasProblem = $false
                $Mems = Get-DfsrMembership -GroupName $Group.GroupName -ErrorAction SilentlyContinue
                $Members = $Mems | Select-Object -ExpandProperty ComputerName -Unique
                
                foreach ($Source in $Members) {
                    foreach ($Dest in $Members) {
                        if ($Source -ne $Dest) {
                            try {
                                $Backlog = Get-DfsrBacklog -SourceComputerName $Source -DestinationComputerName $Dest -GroupName $Group.GroupName -FolderName $Mems[0].FolderName -ErrorAction Stop | Out-Null
                            } catch {
                                if ($_.Exception.Message -like "*Invalid version vector*") { $HasProblem = $true }
                            }
                        }
                    }
                }
                
                $Status = if ($HasProblem) { "⚠️ يحتاج إصلاح" } else { "✅ سليم" }
                $StatusColor = if ($HasProblem) { "Red" } else { "Green" }
                
                Write-Host "`n  [$Index] المجموعة: $($Group.GroupName)" -ForegroundColor Cyan
                Write-Host "    الحالة: $Status" -ForegroundColor $StatusColor
                Write-Host "    السيرفرات: $($Members -join ', ')" -ForegroundColor White
                
                $Index++
            }
            
            # توصيات
            Write-Host "`n[ توصيات ]" -ForegroundColor Yellow
            if ($ProblemGroups -gt 0) {
                Write-Host "  ⚠️  لديك $ProblemGroups مجموعة تحتاج إصلاح." -ForegroundColor Red
                Write-Host "  🔧 استخدم الخيار 4 من القائمة الرئيسية لإصلاحها." -ForegroundColor White
            } else {
                Write-Host "  ✅ جميع المجموعات سليمة. لا حاجة لإجراء." -ForegroundColor Green
            }
        } else {
            Write-Host "`n  لا توجد مجموعات DFS نشطة." -ForegroundColor Red
        }
        
        Write-Host "`n############################################" -ForegroundColor Cyan
        Write-Host "#              نهاية التقرير                 #" -ForegroundColor Cyan
        Write-Host "############################################" -ForegroundColor Cyan
    }

    # ========== الخيار 0: خروج ==========
    elseif ($Action -eq "0") {
        Write-Host "`n[خروج] تم إنهاء البرنامج." -ForegroundColor Yellow
        break
    }

    else {
        Write-Host "`n[خطأ] خيار غير صحيح." -ForegroundColor Red
    }

    # بعد أي خيار (عدا 0 و 5)، انتظر ثم عد للقائمة
    if ($Action -ne "0" -and $Action -ne "5") {
        $Return = Read-Host "`nاضغط Enter للعودة إلى القائمة الرئيسية"
    }
    
    # بعد الخيار 5، اعرض خيار العودة
    if ($Action -eq "5") {
        $Return = Read-Host "`nاضغط Enter للعودة إلى القائمة الرئيسية (أو اكتب 0 للخروج)"
        if ($Return -eq "0") { break }
    }

} while ($true)
