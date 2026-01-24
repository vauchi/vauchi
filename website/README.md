# Vauchi Website

Landing page for Vauchi at [vauchi.app](https://vauchi.app).

## Overview

Static website explaining what Vauchi is and linking to app downloads.

## Development

### Local Preview

```bash
# Using Python
python -m http.server 8000 -d public

# Using Node
npx serve public
```

Then open http://localhost:8000

### Docker

```bash
# Build
docker build -t vauchi-website .

# Run
docker run -p 8080:80 vauchi-website
```

## Deployment

Deployed via Kamal to the same server as vauchi-relay. See [vauchi/infra](https://gitlab.com/vauchi/infra) for deployment config.

```bash
# From infra repo
kamal deploy -c config/deploy.vauchi-landing.yml
```

## Structure

```
public/
├── index.html     # Main landing page
├── css/           # Stylesheets
├── js/            # JavaScript
└── assets/        # Images, fonts
nginx.conf         # Nginx config for Docker
Dockerfile         # Container build
```

## Related Repositories

| Repository | Description |
|------------|-------------|
| [vauchi/code](https://gitlab.com/vauchi/code) | Core Rust library |
| [vauchi/android](https://gitlab.com/vauchi/android) | Android app |
| [vauchi/ios](https://gitlab.com/vauchi/ios) | iOS app |
| [vauchi/docs](https://gitlab.com/vauchi/docs) | Documentation |
| [vauchi/assets](https://gitlab.com/vauchi/assets) | Brand assets, logos |
| [vauchi/infra](https://gitlab.com/vauchi/infra) | Deployment configs |

## Contributing

1. Keep it simple - static HTML/CSS
2. Test locally before submitting
3. Brand assets come from [vauchi/assets](https://gitlab.com/vauchi/assets)

## License

MIT
