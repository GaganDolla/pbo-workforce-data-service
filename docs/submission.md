# Publishing and submission

The project is prepared locally. Repository hosting, collaborator access and the
submission email are the candidate's remaining steps; none is sent automatically.

## Review and verify

1. Read `README.md`, `docs/architecture.md`, `docs/security.md`, and the design answers.
2. Review the AI-use disclosure and ensure it reflects your final work.
3. Run `Rscript scripts/test.R` and `Rscript scripts/import.R` from the project root.
4. Start the API and try both endpoints. Practice explaining the quarterly query
   and how a failed import rolls back.

## Publish with GitHub

Create an empty repository in your GitHub account. A private repository allows you
to share the exercise with the assessors without making the supplied workbook public.
The `Data/data.xlsx` file should be included so the reviewer can reproduce the import.
Do not commit `var/`, local libraries, `.Renviron`, or generated database files.

If Git has not yet been initialized, run:

```sh
git init
git add .
git status --short
git commit -m "Implement R workforce data service"
git branch -M main
```

Review the staged file list before committing. Then use the exact remote URL
shown by GitHub, replacing the placeholder below:

```sh
git remote add origin https://github.com/YOUR-ACCOUNT/YOUR-REPOSITORY.git
git push -u origin main
```

If the repository is private, invite **remy.vanherweghem@parl.gc.ca** as a contributor
using the repository's access settings. Verify the intended recipient has access.

## Submit

Send the repository link to **pbohr@parl.gc.ca** no later than
**October 4, 2026, 11:59 PM Eastern Time**. Only commits before the deadline count.
Confirm the final commit is pushed; a local commit alone is not visible to reviewers.

Suggested email, to review and send yourself:

> Subject: Workforce Data Service exercise submission — [Your name]
>
> Hello,
>
> Please find my Workforce Data Service exercise submission at [repository link].
> The repository includes the application, tests, setup instructions, design-question
> responses and AI-use disclosure. [If private: Contributor access has been invited
> for remy.vanherweghem@parl.gc.ca.]
>
> Thank you,
> [Your name]
