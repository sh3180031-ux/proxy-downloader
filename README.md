# Proxy Downloader

## ⬇️ לדרייב: מדביקים קישור והקובץ מגיע לדרייב

ההורדה רצה על שרת של GitHub, והקובץ עולה ישר ל-Google Drive לתיקייה **הורדות**. לא צריך את `index.html` ולא צריך טוקן.

**שימוש:** [Actions → לדרייב](../../actions/workflows/drive.yml) → **Run workflow** → מדביקים קישור → **Run workflow**.
אחרי שהריצה מסתיימת, בדף הריצה יש קישור לכל קובץ בדרייב.

מה נתמך: יוטיוב ואלפי אתרי וידאו (כולל פלייליסטים), קישורי Google Drive ציבוריים (קבצים ותיקיות), קבצים ישירים (EXE, ZIP, PDF...), magnet. אפשר כמה קישורים עם רווח ביניהם, וסימון "שמע בלבד" נותן MP3.

### הקמה, פעם אחת בלבד

הקוד נמצא בתיקייה [`drive-relay`](drive-relay). זה "גשר" קטן שרץ בחשבון ה-Google שלך ופותח לשרת של GitHub כתובת העלאה לקובץ אחד בכל פעם. הטוקן של הדרייב לא יוצא מ-Google.

1. נכנסים ל-[script.new](https://script.new) (נפתח פרויקט Apps Script חדש).
2. מוחקים את מה שכתוב ומדביקים את כל התוכן של [`drive-relay/Code.gs`](drive-relay/Code.gs).
3. ⚙️ **Project Settings** → מסמנים **Show "appsscript.json" manifest file in editor**. חוזרים לעורך, פותחים את `appsscript.json` ומחליפים את התוכן שלו בתוכן של [`drive-relay/appsscript.json`](drive-relay/appsscript.json). שומרים (Ctrl+S).
4. **Deploy → New deployment** → ⚙️ → **Web app**. מוודאים: *Execute as: Me*, *Who has access: Anyone*. לוחצים **Deploy** ומאשרים את ההרשאות (אם מופיע "Google hasn't verified this app": **Advanced → Go to ... (unsafe)**. זה הסקריפט שלך).
5. בעורך בוחרים בפונקציה `setup` ולוחצים **Run**. ביומן (Execution log) מופיעה שורה שמתחילה ב-`https://script.google.com/...?key=`. מעתיקים אותה.
6. ב-GitHub: **Settings → Secrets and variables → Actions → New repository secret**. שם: `DRIVE_LINK`, ערך: השורה שהעתקת. **Add secret**.

זהו. מעכשיו רק מדביקים קישורים.

> הכתובת עם `?key=` מאפשרת להעלות קבצים לתיקייה "הורדות" בדרייב שלך, לכן שומרים אותה **רק** בסוד ב-GitHub. אם היא דלפה: מוחקים ב-Apps Script את המאפיין `KEY` (Project Settings → Script properties), מריצים שוב `setup` ומעדכנים את הסוד.

---

## ההורדה הרגילה (דרך index.html)

ה-backend של Proxy Downloader: ההורדה רצה על שרת של GitHub Actions, לא על המחשב שלך.
הממשק (`index.html`) נשמר **רק במחשב שלך** ולא נמצא בריפו.

```
index.html  ──repository_dispatch──▶  download.yml (yt-dlp / curl)  ──artifact──▶  index.html ▶ שמירה
```

## מה יש בריפו

| קובץ | תפקיד |
|---|---|
| `.github/workflows/download.yml` | מקבל את הבקשה, מוריד עם yt-dlp (וידאו) או curl (קובץ) ומעלה artifact |
| `.github/workflows/drive.yml` | **לדרייב**: מוריד (זיהוי אוטומטי) ומעלה לדרייב |
| `scripts/fetch.py` | ההורדה עצמה: yt-dlp / gdown / aria2 |
| `drive-relay/` | הגשר לדרייב (Google Apps Script) |
| `.github/workflows/cleanup.yml` | פעם ביום מוחק ריצות ישנות, כדי שהאחסון לא יתמלא |

## הקמה (5 דקות)

1. **יוצרים ריפו חדש** ב-GitHub ומעלים אליו את התיקייה `.github`.
2. **מוודאים ש-Actions פעיל:** Settings → Actions → General → Allow all actions.
3. **יוצרים טוקן:** Settings (של החשבון) → Developer settings → Personal access tokens → **Fine-grained tokens** → Generate:
   - Repository access: רק הריפו הזה
   - Permissions: `Contents: Read and write` ו-`Actions: Read`
4. **פותחים את `index.html` מהמחשב** (לחיצה כפולה), נכנסים לטאב "הגדרות", ממלאים owner, repo וטוקן, ולוחצים על "שמור" ואז על "בדיקת חיבור". הטוקן נשמר רק בדפדפן שלך.

### תוכן שדורש התחברות (YouTube וכו')

ייתכן ש-YouTube יחסום את שרתי GitHub בהודעה "Sign in to confirm you're not a bot". במקרה כזה:
מייצאים cookies בפורמט Netscape (`cookies.txt`) ושומרים אותם ב-Settings → Secrets and variables → Actions → New secret בשם `YT_COOKIES`.

## הגבלות שחשוב לדעת

אי אפשר לקבל הורדה "ללא הגבלה בכלל". אלה הגבולות של GitHub:

| | ריפו **ציבורי** | ריפו **פרטי** (חינמי) |
|---|---|---|
| דקות Actions | ללא הגבלה | 2,000 דקות בחודש |
| אחסון artifacts | ללא חיוב | 500MB (נמחק אחרי יום אחד, לכן זה כמעט לא מורגש) |
| פרטיות | **כל אחד יכול לראות אילו קישורים הורדת**, ומשתמש מחובר יכול להוריד את הקבצים | רק את/ה |

גבולות נוספים לכל ריצה: עד שעתיים לריצה (מוגדר ב-workflow, ו-GitHub מאפשר עד 6 שעות), כ-14GB מקום פנוי בדיסק, וכמה ריצות במקביל.

**תנאי השימוש של GitHub** אוסרים להשתמש ב-Actions לפעילות שלא קשורה לפיתוח תוכנה בריפו. שימוש כבד ככלי הורדות עלול לגרום לחסימה של Actions בחשבון או של החשבון כולו. כדאי להשתמש בחשבון נפרד ובמידה סבירה.

## הפעלה ידנית (בלי האתר)

Actions → download → Run workflow, ממלאים URL ומצב, ואחרי הריצה מורידים את ה-artifact מדף הריצה.

## אם "הורד עכשיו עם הטוקן" נכשל

לפעמים הדפדפן חוסם את משיכת ה-zip (CORS). במקרה כזה לוחצים על "פתח את דף הריצה" ומורידים את ה-artifact משם, כשאת/ה מחובר/ת ל-GitHub.
