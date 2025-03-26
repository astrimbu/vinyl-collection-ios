# Vinyl Collection Manager for iOS

A beautiful iOS app to manage your vinyl record collection.

## Features

- Browse and manage your vinyl collection
- Integration with Discogs API for album artwork and track information
- Beautiful modern UI with iOS design guidelines
- Track listing support
- Album artwork display

## Setup

### Prerequisites

- Xcode 14.0 or later
- iOS 15.0 or later
- A Discogs API token

### Environment Setup

1. Copy the `.env.example` file to `.env`:
   ```bash
   cp .env.example .env
   ```

2. Add your Discogs API token to the `.env` file:
   ```
   DISCOGS_API_TOKEN=your_token_here
   ```

   You can obtain a Discogs API token by:
   1. Creating a Discogs account at https://www.discogs.com
   2. Going to your Developer settings
   3. Generating a new token

### Building the Project

1. Open `Vinyls.xcodeproj` in Xcode
2. Select your target device or simulator
3. Build and run (⌘R)

## Architecture

The app follows modern iOS development practices:

- SwiftUI for the user interface
- Async/await for network operations
- MVVM architecture
- Discogs API integration for metadata

## Discogs Integration

The app integrates with the Discogs API to fetch:
- Album artwork
- Track listings
- Release information

Rate limiting is handled automatically (60 requests per minute).

## Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a new Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Related Projects

- [vinyl-collection](https://github.com/astrimbu/vinyl-collection) - Web version of the vinyl collection manager 