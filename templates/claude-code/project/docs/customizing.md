# Customizing

## 1. Configuration

*Describe each `.env` variable and what effect changing it has. Copy variable names exactly from `.env.example`.*

| Variable | Default | Effect |
|----------|---------|--------|
| (example) `LOG_LEVEL` | `INFO` | Sets verbosity: DEBUG, INFO, WARNING, ERROR |

## 2. Extension points

*Where should a developer add new features? Name the files or modules to touch and the pattern to follow.*

- To add a new command: (e.g. add a function to `main.py` and register it in ...)
- To add a new output format: (e.g. subclass `BaseExporter` in `exporters/`)

## 3. Changing default behaviour

*List any flags, environment variables, or config files that alter how the project runs beyond what is in section 1.*

- (example) Pass `--dry-run` to skip writes and log actions only.
- (example) Set `FEATURE_X=true` in `.env` to enable the experimental pipeline.
