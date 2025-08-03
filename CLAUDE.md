# Marvel Champions Online

## Project Overview

A web-based "smart table" application for playing Marvel Champions: The Card Game online. The app provides digital deck and game state management without enforcing game rules - players manage rules themselves. Built for personal use with potential for multiplayer expansion.

## Technical Stack

- **Backend**: Elixir/Phoenix LiveView
- **Frontend**: Phoenix LiveView + Custom JavaScript for interactions
- **Database**: PostgreSQL (normalized schema, database as source of truth)
- **Real-time**: Phoenix PubSub for state synchronization
- **State Management**: GenServer processes per game + database persistence

## Architecture Principles

- **Database First**: PostgreSQL is the authoritative source of game state
- **Process Per Game**: Each game runs in a supervised GenServer
- **Smart Table Approach**: App manages cards/tokens/zones, players enforce rules
- **Dual Mode Support**: Designed for both synchronous and asynchronous multiplayer

## Core Features (MVP)

### Game Management
- Create/join games
- Load deck compositions
- Save/resume games

### Zone Management
- Simplified zones: Identity, Player Area, Villain Area, Main Scheme, Side Schemes, Encounter
- Card movement between zones
- Proper visibility rules (hands private, play areas public)

### Card Interactions
- Drag-and-drop card movement
- Token/counter management (damage, threat, etc.)
- Card state changes (exhaust, flip)
- Card inspection (full text view)

### State Tracking
- Player health
- Villain health and stage
- Scheme threat and progression
- Turn/phase management

## Development Phases

### Phase 1: Foundation (Weeks 1-2)
- Basic Phoenix app with LiveView
- Core database schema and migrations
- Card definition seeding (small subset)
- Basic game creation and zone display

### Phase 2: Core Mechanics (Weeks 3-4)
- GenServer game processes
- Basic card movement between zones
- Simple deck loading into games
- State persistence and recovery

### Phase 3: Enhanced Interactions (Weeks 5-6)
- Drag-and-drop with JavaScript hooks
- Token management UI
- Card state changes (exhaust, flip)
- Turn/phase progression

### Phase 4: Polish & Multiplayer (Weeks 7-8)
- Real-time multiplayer synchronization
- Improved UI/UX
- Game history and action log
- Error handling and edge cases

## Key Technical Decisions

- **State Authority**: Database is source of truth, GenServer caches for performance
- **Persistence Strategy**: Write-through on actions, batch for performance later
- **Process Lifecycle**: Aggressive hibernation, restart from DB on crash
- **UI Boundaries**: Server handles game logic, client handles smooth interactions
- **Multiplayer**: PubSub for real-time updates, async support via action queuing

## Open Questions

- Action batching strategy for performance
- Token storage: JSONB vs separate table (starting with JSONB)
- Mobile responsiveness requirements
- Deck import/export formats
- Asset management for card images

## Success Criteria

**MVP Success**: 
- Solo play works end-to-end
- Basic card interactions feel responsive
- Games persist through server restarts
- Simple deck building and loading

**Full Success**:
- Smooth multiplayer experience
- Rich card interactions (drag-drop, context menus)
- Comprehensive game state tracking
- Robust error handling and recovery

## Key Architecture Components

### Ash Framework Integration
- **Domain**: `Sanctum.Accounts` manages user resources and tokens
- **Resources**: User and Token models with authentication strategies
- **Authentication**: Magic link, password confirmation, and session-based auth
- **Admin Interface**: AshAdmin available at `/admin` in development

### Phoenix Application Structure
- **Endpoint**: `SanctumWeb.Endpoint` with LiveView socket, static assets, and development tools
- **Router**: Routes include authentication flows, game interface, and development dashboards
- **Live Views**: Primary interface via `SanctumWeb.GameLive.Index`
- **Authentication**: AshAuthentication.Phoenix integration with custom overrides

### Background Jobs
- **Oban**: Job processing with PostgreSQL backend
- **AshOban**: Integration for Ash-based background jobs
- **Queues**: Default queue with 10 workers

### Security
- **CSP**: Custom Content Security Policy plug with environment-specific policies
- **Session**: Secure cookie-based sessions with CSRF protection

## Development Commands

### Setup and Dependencies
```bash
mix setup                    # Full project setup: deps, database, assets
mix deps.get                # Install dependencies only
mix ash.setup               # Setup Ash resources and database
```

### Development Server
```bash
mix phx.server              # Start Phoenix server
iex -S mix phx.server       # Start with IEx console
```

### Database Operations
```bash
mix ecto.setup              # Create, migrate, and seed database
mix ecto.reset              # Drop and recreate database
mix ash.setup --quiet       # Quiet Ash setup for testing
```

### Assets and Frontend
```bash
mix assets.setup            # Install Tailwind and esbuild
mix assets.build            # Build CSS and JS assets
mix assets.deploy           # Build and minify for production
```

### Testing and Quality
```bash
mix test                    # Run test suite (includes ash.setup)
mix ck                      # Run formatter, Credo, and Sobelow checks
mix credo suggest --min-priority=normal  # Code quality analysis
mix sobelow --config --exit # Security analysis
mix format                  # Format code
```

### Development Tools
```bash
mix dialyzer                # Static analysis (PLT files in priv/plts/)
mix coveralls               # Test coverage reports
```

## Development Environment

### Docker Support
- PostgreSQL database via docker-compose
- Adminer database interface on port 8080
- Production Dockerfile with multi-stage build

### Development Dashboard Access
- **Live Dashboard**: `/dev/dashboard` - Phoenix metrics and debugging
- **Oban Dashboard**: `/oban` - Background job monitoring  
- **Ash Admin**: `/admin` - Resource management interface
- **Mailbox Preview**: `/dev/mailbox` - Email preview in development

### Asset Pipeline
- **Tailwind**: CSS framework with custom fonts (Metropolis, Exo2, Komika, Elektra)
- **esbuild**: JavaScript bundling with ES2022 target
- **Static Assets**: Custom fonts and images in `priv/static/`

## Configuration Notes

### Environment-Specific Behavior
- **Development**: Includes live reload, code reloader, and development dashboards
- **Production**: Optimized CSP, minified assets, and secure headers
- **Test**: Ash setup runs quietly, Ecto sandbox mode

### Authentication Flow
- Magic link email authentication via Swoosh mailer
- Session-based authentication with secure cookies
- User registration, password reset, and confirmation workflows
- API authentication via bearer tokens

### Code Quality Tools
- **Credo**: Configured with low priority for TODOs and module docs
- **Sobelow**: Security analysis with configuration
- **ExCoveralls**: Test coverage with multiple output formats
- **Dialyzer**: Type analysis with custom PLT locations
