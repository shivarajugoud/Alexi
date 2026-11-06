"""A localhost-only, review-gated LangGraph service for Alexi.

The graph is deliberately unable to access the filesystem or execute a patch. Swift
passes a bounded text preview; the only output is a plan that the person reviews.
"""

from __future__ import annotations

import os
from typing import Any, TypedDict
from urllib.parse import urlparse

import uvicorn
from fastapi import FastAPI, HTTPException
from langchain_ollama import ChatOllama
from langgraph.graph import END, START, StateGraph
from pydantic import BaseModel, Field


class PatchPlanState(TypedDict, total=False):
    instruction: str
    selected_file_path: str
    selected_file_contents: str
    workspace_context: str
    model: str
    plan: str
    review_required: bool
    events: list[str]


class PatchPlanRequest(BaseModel):
    instruction: str = Field(min_length=1, max_length=4_000)
    selected_file_path: str = Field(min_length=1, max_length=4_000)
    selected_file_contents: str = Field(max_length=4_000)
    workspace_context: str = Field(max_length=4_000)
    model: str = Field(min_length=1, max_length=200)


class PatchPlanResponse(BaseModel):
    plan: str
    review_required: bool
    events: list[str]


def local_ollama_base_url() -> str:
    base_url = os.environ.get("ALEXI_OLLAMA_BASE_URL", "http://127.0.0.1:11434")
    host = urlparse(base_url).hostname
    if host not in {"127.0.0.1", "localhost", "::1"}:
        raise RuntimeError("ALEXI_OLLAMA_BASE_URL must point to localhost")
    return base_url.rstrip("/")


def prepare_context(state: PatchPlanState) -> PatchPlanState:
    return {
        "events": [*state.get("events", []), "bounded_workspace_context_received"],
        "review_required": True,
    }


def create_plan(state: PatchPlanState) -> PatchPlanState:
    prompt = f"""You are Alexi's local patch-planning node. Produce a concise plan only.
Never claim to apply, execute, or save a change. Do not include shell commands.

Return these sections:
1. Summary
2. Exact file target
3. Intended change
4. Risk notes
5. Human review checklist

Instruction: {state['instruction']}
File target: {state['selected_file_path']}
File preview:\n{state['selected_file_contents']}
Workspace context:\n{state['workspace_context']}
"""
    model = ChatOllama(
        model=state["model"],
        base_url=local_ollama_base_url(),
        temperature=0,
    )
    response = model.invoke(prompt)
    content = response.content
    if not isinstance(content, str):
        content = str(content)
    return {
        "plan": content.strip(),
        "events": [*state.get("events", []), "local_model_plan_created"],
        "review_required": True,
    }


def hold_for_review(state: PatchPlanState) -> PatchPlanState:
    return {
        "events": [*state.get("events", []), "human_review_required"],
        "review_required": True,
    }


def build_graph() -> Any:
    graph = StateGraph(PatchPlanState)
    graph.add_node("prepare_context", prepare_context)
    graph.add_node("create_plan", create_plan)
    graph.add_node("hold_for_review", hold_for_review)
    graph.add_edge(START, "prepare_context")
    graph.add_edge("prepare_context", "create_plan")
    graph.add_edge("create_plan", "hold_for_review")
    graph.add_edge("hold_for_review", END)
    return graph.compile()


patch_plan_graph = build_graph()
app = FastAPI(title="Alexi local LangGraph sidecar", docs_url=None, redoc_url=None)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "scope": "localhost-only plan service"}


@app.post("/plan", response_model=PatchPlanResponse)
def plan(request: PatchPlanRequest) -> PatchPlanResponse:
    try:
        result = patch_plan_graph.invoke(request.model_dump())
    except Exception as error:
        raise HTTPException(status_code=503, detail=f"Local planning unavailable: {error}") from error
    return PatchPlanResponse(
        plan=result.get("plan", ""),
        review_required=bool(result.get("review_required", True)),
        events=result.get("events", []),
    )


if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=int(os.environ.get("ALEXI_LANGGRAPH_PORT", "8787")))
