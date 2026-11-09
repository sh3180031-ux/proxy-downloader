// Drive relay for proxy-downloader.
// GitHub asks for an upload URL for ONE file; this script opens it in the Drive folder below.
// The Drive token never leaves Google.
const FOLDER_NAME = '\u05D4\u05D5\u05E8\u05D3\u05D5\u05EA'; // folder name in Drive

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
      muteHttpExceptions: true
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

// Run once after Deploy. Creates the key and prints the value for the GitHub secret DRIVE_LINK.
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
    Logger.log('Deploy first (Deploy > New deployment > Web app), then run setup again.');
    return;
  }
  Logger.log('Copy the next line into the GitHub secret DRIVE_LINK:');
  Logger.log(url.replace(/\/dev$/, '/exec') + '?key=' + key);
}
