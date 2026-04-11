"""
QSN Rugby Content Factory — Live LangGraph Demo
================================================
A real multi-agent pipeline that:
  1. Routes game content to the right type
  2. Analyzes the match
  3. Writes a YouTube title
  4. Writes a full video description
  5. Designs a thumbnail concept

HOW TO RUN:
  export ANTHROPIC_API_KEY="your-key-here"
  python qsn_agent.py

OR pass a custom game:
  python qsn_agent.py --game "All Blacks 45-12 Wallabies, hat-trick by Ardie Savea"
"""

import os
import sys
import json
import time
import logging
import argparse
from typing import TypedDict, Literal
from langgraph.graph import StateGraph, END, START
import anthropic

# ============================================================
# STRUCTURED LOGGING — production-grade from day one
# ============================================================
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(levelname)s %(message)s'
)
logger = logging.getLogger("qsn_agent")

def log_agent(agent_name: str, status: str, **kwargs):
    """Emit a structured JSON log — queryable in Azure Monitor."""
    logger.info(json.dumps({
        "agent": agent_name,
        "status": status,
        "timestamp": time.time(),
        **kwargs
    }))


# ============================================================
# STEP 1 — STATE (The Shared Notebook)
# ============================================================
class QSNState(TypedDict):
    game_info: str
    content_type: str       # "highlights" | "analysis" | "player_spotlight"
    analysis: str
    title: str
    description: str
    thumbnail_concept: str
    total_tokens: int
    messages: list


# ============================================================
# STEP 2 — CLAUDE CLIENT
# ============================================================
def get_client():
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print("\n❌  Missing ANTHROPIC_API_KEY")
        print("   Run:  export ANTHROPIC_API_KEY='sk-ant-...'")
        sys.exit(1)
    return anthropic.Anthropic(api_key=api_key)

def ask_claude(client, system_prompt: str, user_message: str) -> tuple[str, int]:
    """Call Claude and return (response_text, total_tokens)."""
    start = time.time()
    response = client.messages.create(
        model="claude-haiku-4-5-20251001",   # fast + cheap for the demo
        max_tokens=600,
        system=system_prompt,
        messages=[{"role": "user", "content": user_message}]
    )
    latency_ms = round((time.time() - start) * 1000)
    tokens = response.usage.input_tokens + response.usage.output_tokens
    return response.content[0].text, tokens, latency_ms


# ============================================================
# STEP 3 — THE AGENTS (Nodes)
# ============================================================

def router_agent(state: QSNState) -> QSNState:
    print("\n🏉  [1/5] ROUTER AGENT — deciding content type...")
    client = get_client()

    text, tokens, ms = ask_claude(
        client,
        system_prompt="""You are a rugby content producer for QSN — America's biggest rugby YouTube channel.
Read the game info and decide what type of content will perform best.
Reply with ONLY one word: highlights, analysis, or player_spotlight

- highlights      → exciting high-scoring games
- analysis        → tactical, upset, or controversial matches
- player_spotlight → one player had a standout/historic performance""",
        user_message=f"Game: {state['game_info']}"
    )

    content_type = text.strip().lower()
    if content_type not in ["highlights", "analysis", "player_spotlight"]:
        content_type = "highlights"

    log_agent("router", "success", content_type=content_type, tokens=tokens, latency_ms=ms)
    print(f"   → Content type: {content_type.upper()}  ({tokens} tokens, {ms}ms)")

    return {
        **state,
        "content_type": content_type,
        "total_tokens": state["total_tokens"] + tokens,
        "messages": state["messages"] + [f"Router → {content_type}"]
    }


def analyst_agent(state: QSNState) -> QSNState:
    print("\n📊  [2/5] ANALYST AGENT — breaking down the game...")
    client = get_client()

    text, tokens, ms = ask_claude(
        client,
        system_prompt="""You are a rugby analyst for QSN YouTube.
Write 3-4 punchy, fan-friendly sentences about this game.
Focus on: key moments, standout players, turning points, emotional storylines.
Write like you're hyping up passionate rugby fans.""",
        user_message=f"Game: {state['game_info']}\nContent type: {state['content_type']}"
    )

    log_agent("analyst", "success", tokens=tokens, latency_ms=ms)
    print(f"   → Analysis written  ({tokens} tokens, {ms}ms)")
    print(f"   Preview: {text[:90]}...")

    return {
        **state,
        "analysis": text,
        "total_tokens": state["total_tokens"] + tokens,
        "messages": state["messages"] + ["Analyst → analysis complete"]
    }


def title_agent(state: QSNState) -> QSNState:
    print("\n✏️   [3/5] TITLE AGENT — writing the YouTube title...")
    client = get_client()

    text, tokens, ms = ask_claude(
        client,
        system_prompt="""You are a YouTube title specialist for QSN rugby channel.
Write ONE title that is:
- Under 70 characters
- Exciting — makes fans click
- Specific (team names, scores, or player names)
- ONE key word in ALL CAPS
- Truthful — no fake drama
Return ONLY the title, nothing else.""",
        user_message=f"Game: {state['game_info']}\nType: {state['content_type']}\nAnalysis: {state['analysis']}"
    )

    title = text.strip()
    log_agent("title", "success", title=title, tokens=tokens, latency_ms=ms)
    print(f"   → Title: {title}  ({tokens} tokens, {ms}ms)")

    return {
        **state,
        "title": title,
        "total_tokens": state["total_tokens"] + tokens,
        "messages": state["messages"] + [f"Title → {title}"]
    }


def description_agent(state: QSNState) -> QSNState:
    print("\n📝  [4/5] DESCRIPTION AGENT — writing the video description...")
    client = get_client()

    text, tokens, ms = ask_claude(
        client,
        system_prompt="""You are a YouTube description writer for QSN rugby channel.
Write a description with:
1. 2-sentence hook (most exciting part of the game)
2. 4 timestamps: 0:00 Intro | X:XX Key Moment | etc
3. A call to action (subscribe, like, comment)
4. 5 relevant hashtags
Keep under 200 words. Sound authentic to rugby culture.""",
        user_message=f"Title: {state['title']}\nGame: {state['game_info']}\nAnalysis: {state['analysis']}"
    )

    log_agent("description", "success", tokens=tokens, latency_ms=ms)
    print(f"   → Description written  ({tokens} tokens, {ms}ms)")

    return {
        **state,
        "description": text,
        "total_tokens": state["total_tokens"] + tokens,
        "messages": state["messages"] + ["Description → complete"]
    }


def thumbnail_agent(state: QSNState) -> QSNState:
    print("\n🖼️   [5/5] THUMBNAIL AGENT — designing the visual concept...")
    client = get_client()

    text, tokens, ms = ask_claude(
        client,
        system_prompt="""You are a YouTube thumbnail art director for QSN rugby.
Describe the thumbnail in ONE paragraph covering:
- Main image (action shot, player moment, or reaction)
- Text overlay (2-4 words MAX, color, position on screen)
- Background / color scheme
- Emotion it should convey
Be specific and visual — you're directing a photo editor.""",
        user_message=f"Title: {state['title']}\nGame: {state['game_info']}\nType: {state['content_type']}"
    )

    log_agent("thumbnail", "success", tokens=tokens, latency_ms=ms)
    print(f"   → Thumbnail concept ready  ({tokens} tokens, {ms}ms)")

    return {
        **state,
        "thumbnail_concept": text,
        "total_tokens": state["total_tokens"] + tokens,
        "messages": state["messages"] + ["Thumbnail → complete"]
    }


# ============================================================
# STEP 4 — ROUTING FUNCTION
# ============================================================
def route_content(state: QSNState) -> Literal["analyst_agent"]:
    """
    In this version all content types go to analyst.
    In production you could route player_spotlight to a
    dedicated player-stats agent, or analysis to a
    tactics agent that pulls external data.
    """
    return "analyst_agent"


# ============================================================
# STEP 5 — BUILD THE GRAPH
# ============================================================
def build_graph():
    graph = StateGraph(QSNState)

    # Register all nodes
    graph.add_node("router_agent",      router_agent)
    graph.add_node("analyst_agent",     analyst_agent)
    graph.add_node("title_agent",       title_agent)
    graph.add_node("description_agent", description_agent)
    graph.add_node("thumbnail_agent",   thumbnail_agent)

    # Wire the pipeline
    graph.add_edge(START, "router_agent")
    graph.add_conditional_edges("router_agent", route_content)
    graph.add_edge("analyst_agent",     "title_agent")
    graph.add_edge("title_agent",       "description_agent")
    graph.add_edge("description_agent", "thumbnail_agent")
    graph.add_edge("thumbnail_agent",   END)

    return graph.compile()


# ============================================================
# STEP 6 — HEALTH CHECK ENDPOINT (for Kubernetes)
# ============================================================
def health_check():
    """
    Kubernetes will call GET /health every 30 seconds.
    Returns 200 = pod is alive. Fails 3x = K8s restarts pod.
    """
    from http.server import HTTPServer, BaseHTTPRequestHandler
    import threading

    class HealthHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == "/health":
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'{"status":"healthy","service":"qsn-agent"}')
            else:
                self.send_response(404)
                self.end_headers()
        def log_message(self, *args): pass  # suppress HTTP logs

    server = HTTPServer(("0.0.0.0", 8080), HealthHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    print("💚  Health check server running on :8080/health")


# ============================================================
# STEP 7 — RUN
# ============================================================
def run(game_info: str):
    print("=" * 62)
    print("  🏉  QSN RUGBY CONTENT FACTORY  —  LANGGRAPH LIVE DEMO")
    print("=" * 62)
    print(f"\n📋  Game: {game_info.strip()}\n")

    app = build_graph()
    start_time = time.time()

    initial_state: QSNState = {
        "game_info": game_info,
        "content_type": "",
        "analysis": "",
        "title": "",
        "description": "",
        "thumbnail_concept": "",
        "total_tokens": 0,
        "messages": []
    }

    final = app.invoke(initial_state)
    total_ms = round((time.time() - start_time) * 1000)

    print("\n" + "=" * 62)
    print("  ✅  CONTENT PACKAGE COMPLETE")
    print("=" * 62)
    print(f"\n📺  TYPE:        {final['content_type'].upper()}")
    print(f"\n🎬  TITLE:\n    {final['title']}")
    print(f"\n📝  DESCRIPTION:\n{final['description']}")
    print(f"\n🖼️   THUMBNAIL:\n{final['thumbnail_concept']}")
    print(f"\n📊  PIPELINE:   {' → '.join(final['messages'])}")
    print(f"⚡  TOTAL TIME: {total_ms}ms  |  TOTAL TOKENS: {final['total_tokens']}")
    print()

    return final


if __name__ == "__main__":
    import time
    health_check()  # start the health server
    print("💚  QSN Agent server ready — health check on :8080/health")
    while True:
        time.sleep(60)  # keep the container alive permanently

    if args.health:
        health_check()

    game = args.game or """
    USA Eagles vs Canada Maple Leafs — Americas Rugby Championship 2025.
    Final score: USA 38-14. Eagles winger Marcus Tupuola scored a hat-trick (3 tries).
    USA dominated from kick-off. Canada fly-half yellow-carded twice.
    Attendance: 12,000 in New Orleans.
    """
    run(game)
