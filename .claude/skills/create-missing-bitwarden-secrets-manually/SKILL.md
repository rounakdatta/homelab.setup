Sometimes you might realize that certain Bitwarden secrets which ought to be there, are missing. This only happens the first time we are introducing a new tool. In that case, you should just use the `bw` CLI to create the password. You should take care in selecting the vault to be `taptappers.club`. Also, under any circumstances, DO NOT DELETE ANYTHING by yourself, especially in other vaults. Only when there's an explicit command by me to replace/delete something, then only do this destructive action, otherwise never.

To make sure `bw` CLI is authenticated properly, you can use the environment variables. When running in a local setup, you'd in most cases find a .env file, and in remote machines (like CI/CD), these would be explicitly passed.

```
      - name: Set up Bitwarden
        id: bitwarden
        env:
          BW_EMAIL: ${{ secrets.BW_EMAIL }}
          BW_PW: ${{ secrets.BW_PW }}
          BW_CLIENTID: ${{ secrets.BW_CLIENTID }}
          BW_CLIENTSECRET: ${{ secrets.BW_CLIENTSECRET }}
        run: |
          npm install -g @bitwarden/cli
          bw login --apikey >/dev/null
          export BW_SESSION=$(bw unlock --raw "${BW_PW}") >/dev/null
          echo "BW_SESSION=${BW_SESSION}" >> ${GITHUB_ENV}
          echo "::add-mask::${BW_SESSION}"
          bw sync
```

I think above are the steps to correctly set up bitwarden for all CLI operations. You might not need sync, but you might need th remaining to actually create and retrieve passwords.