# Free web link (no Tiiny, no `rizbismii` in the URL)

GitHub’s default link always includes your username (`rizbismii.github.io/...`).  
To get a **free** link **without** `rizbismii`, use a free GitHub Organization site.

## Your link will be

**https://expirycheck.github.io/**

## Do this once (about 2 minutes)

### 1. Create a free organization
1. Open: https://github.com/organizations/plan  
2. Choose the **free** plan  
3. Organization name: **`expirycheck`**  
4. Complete create

### 2. Create the website repo
1. Open: https://github.com/organizations/expirycheck/repositories/new  
2. Repository name must be exactly: **`expirycheck.github.io`**  
3. Public → Create repository

### 3. Upload the web app
1. Download the latest **`ExpiryCheck-web.zip`** from GitHub Releases  
   (or use the `docs/` folder from this project)  
2. On the new repo page → **Add file** → **Upload files**  
3. Upload **everything inside** the zip (so `index.html` is at the repo root)  
4. Commit

### 4. Turn on Pages
1. Repo **Settings → Pages**  
2. Source: **Deploy from a branch**  
3. Branch: **main** (or `master`), folder: **/ (root)** → **Save**

Wait 1–2 minutes, then open:

## https://expirycheck.github.io/

PCs on the same shop use that link. Inventory still syncs through your existing free Supabase cloud sync.
