# Azure Deployment TODO

## Overview

Deploy Bakable backend to Azure using Claude Agent SDK with Microsoft Foundry.

## Architecture

```
Desktop App  ←→  Azure Container  ←→  Microsoft Foundry (Claude)
     ↑                 ↓
     └──── MCP Relay ──┘
              ↓
        Studio Plugin
```

## Tasks

### 1. Azure Setup
- [ ] Create Azure Container App or AKS cluster
- [ ] Configure Microsoft Entra authentication
- [ ] Enable Microsoft Foundry access for Claude models
- [ ] Set up managed identity for auth

### 2. Environment Configuration
- [ ] Set `CLAUDE_CODE_USE_FOUNDRY=1`
- [ ] Configure Azure auth (managed identity or service principal)
- [ ] Set up environment variables for MCP relay WebSocket URL

### 3. Backend Deployment
- [ ] Containerize daemon (`Dockerfile`)
- [ ] Push to Azure Container Registry
- [ ] Deploy to Container App
- [ ] Configure networking (public endpoint for desktop connections)

### 4. MCP Relay
- [ ] Desktop connects to Azure via WebSocket
- [ ] Azure relays MCP tool calls to desktop
- [ ] Desktop forwards to Studio plugin
- [ ] Handle reconnection/auth

### 5. File Sync
- [ ] Desktop syncs project files to Azure container
- [ ] Azure container has working directory with files
- [ ] File changes sync back to desktop
- [ ] Rojo picks up changes locally

### 6. Security
- [ ] HTTPS/WSS for all connections
- [ ] Auth tokens for desktop → Azure
- [ ] Rate limiting
- [ ] Audit logging

## Environment Variables (Azure Container)

```bash
CLAUDE_CODE_USE_FOUNDRY=1
PORT=3000
# Azure auth via managed identity (no explicit keys needed)
```

## Resources

- [Claude in Microsoft Foundry](https://azure.microsoft.com/en-us/blog/introducing-claude-opus-4-5-in-microsoft-foundry/)
- [Claude Agent SDK](https://platform.claude.com/docs/en/agent-sdk/overview)
- [Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/)
