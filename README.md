# Proxy Downloader

אתר שמריץ את ההורדה על שרת של GitHub Actions, לא על המחשב שלך. כשההורדה מסתיימת, הקובץ חוזר אליך לדפדפן.

```
index.html  ──repository_dispatch──▶  download.yml (yt-dlp / curl)  ──artifact──▶  index.html ▶ שמירה
```

## מה יש בריפו

| קובץ | תפקיד |
|---|---|
| `index.html` | הממשק: וידאו, קובץ והגדרות |
| `.github/workflows/download.yml` | מקבל את הבקשה, מוריד עם yt-dlp (וידאו) או curl (קובץ) ומעלה artifact |
| `.github/workflows/cleanup.yml` | פעם ביום מוחק ריצות ישנות, כדי שהאחסון לא יתמלא |

## הקמה (5 דקות)

1. **יוצרים ריפו חדש** ב-GitHub (למשל `proxy-downloader`) ומעלים אליו את כל הקבצים, כולל התיקייה `.github`.
2. **מוודאים ש-Actions פעיל:** Settings → Actions → General → Allow all actions.
3. **יוצרים טוקן:** Settings (של החשבון) → Developer settings → Personal access tokens → **Fine-grained tokens** → Generate:
   - Repository access: רק הריפו הזה
   - Permissions: `Contents: Read and write` ו-`Actions: Read`
4. **פותחים את `index.html`**, נכנסים לטאב "הגדרות", ממלאים owner, repo וטוקן, ולוחצים על "שמור" ואז על "בדיקת חיבור".
5. **אופציונלי, כדי לגשת מכל מקום:** Settings → Pages → Deploy from branch → `main` / root. האתר יהיה זמין בכתובת
   `https://<owner>.github.io/<repo>/`. (בריפו פרטי, Pages דורש מנוי בתשלום. אפשר גם פשוט לפתוח את `index.html` מקומית.)

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
