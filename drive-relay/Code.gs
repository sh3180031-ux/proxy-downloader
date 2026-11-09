// גשר הורדות לדרייב.
// השרת של GitHub מבקש "חלון העלאה" לקובץ אחד, והסקריפט פותח אותו בתיקייה "הורדות".
// הטוקן של הדרייב לא יוצא מ-Google; GitHub מקבל רק כתובת העלאה חד-פעמית לקובץ אחד.
const FOLDER_NAME = 'הורדות';  // שם התיקייה בדרייב

function doGet(e) {
  const key = PropertiesService.getScriptProperties().getProperty('KEY');
  const p = (e && e.parameter) || {};
  if (!key || p.key !== key) return json_({ error: 'forbidden' });

  const name = String(p.name || 'download').slice(0, 250);
  const headers = { Authorization: 'Bearer ' + ScriptApp.getOAuthToken() };
  if (p.size) headers['X-Upload-Content-Length'] = String(p.size);
  const res = UrlFetchApp.fetch(
    'https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&fields=id,name,size,webViewLink',
    {
      method: 'post',
      contentType: 'application/json; charset=UTF-8',
      headers: headers,
      payload: JSON.stringify({ name: name, parents: [getFolder_().getId()] }),
      muteHttpExceptions: true,
    });
  if (res.getResponseCode() !== 200) return json_({ error: res.getContentText() });
  const h = res.getAllHeaders();
  return json_({ upload_url: h['Location'] || h['location'] });
}

function json_(o) {
  return ContentService.createTextOutput(JSON.stringify(o)).setMimeType(ContentService.MimeType.JSON);
}

function getFolder_() {
  const root = DriveApp.getRootFolder();
  const it = root.getFoldersByName(FOLDER_NAME);
  return it.hasNext() ? it.next() : root.createFolder(FOLDER_NAME);
}

// מריצים פעם אחת אחרי הפריסה (Deploy). מייצר מפתח ומדפיס את הערך לסוד DRIVE_LINK ב-GitHub.
function setup() {
  const props = PropertiesService.getScriptProperties();
  let key = props.getProperty('KEY');
  if (!key) {
    key = Utilities.getUuid().replace(/-/g, '') + Utilities.getUuid().replace(/-/g, '');
    props.setProperty('KEY', key);
  }
  getFolder_();
  const url = ScriptApp.getService().getUrl();
  if (!url) {
    Logger.log('קודם צריך לפרוס: Deploy ← New deployment ← Web app, ואז להריץ שוב את setup.');
    return;
  }
  Logger.log('העתק את השורה הבאה לסוד בשם DRIVE_LINK ב-GitHub:');
  Logger.log(url.replace(/\/dev$/, '/exec') + '?key=' + key);
}
