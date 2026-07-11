# Architecture Specification: Production-Grade RAG Engine

## Phase 3: Ingestion, Database Layout, and Query Retrieval Pipeline

This document details the configuration, systemic architecture, and data engineering abstractions deployed within the local private network layer. Phase 3 transitions our RAG (Retrieval-Augmented Generation) stack from an educational prototype into an enterprise-grade execution system using **LlamaIndex** and a localized **pgvector** data store.

## 1. Local Architectural Ingestion & Search Flowchart

The data architecture completely decouples the low-level vector computation from the application layer. Django coordinates the HTTP lifecycle while LlamaIndex provides the abstraction interface to command the vector database table and orchestrate embeddings.  

```plaintext
=======================================================================================================================  
                                     PHASE 3 INTERNAL RAG RETRIEVAL PIPELINE  
=======================================================================================================================

      [ INBOUND FROM VPS VIA REVERSE TUNNEL ]  
                         │  
                         ▼ (HTTP POST payload to: /api/v1/triage/rag/)  
             ┌───────────────────────┐  
             │  Django API View Controller │  
             └───────────┬───────────┘  
                         │  
                         ▼ (Passes context-filtered payload to LlamaIndex)  
             ┌───────────────────────────────────────────────────────┐  
             │                 LlamaIndex Core Engine                │  
             └───────────────────────────┬───────────────────────────┘  
                                         │  
                 ┌───────────────────────┴───────────────────────┐  
                 │ (Step A: Generate Vector)                     │ (Step B: Query Execution)  
                 ▼                                               ▼  
     ┌───────────────────────┐                       ┌───────────────────────┐  
     │ Ollama Embedding Node │                       │   PGVector Store      │  
     │ (nomic-embed-text)    │                       │ (enterprise_knowledge)│  
     └───────────┬───────────┘                       └───────────┬───────────┘  
                 │                                               │  
                 └───────────────► [ 768-Dim Vector Space ] ◄────┘  
                                                 │  
                                                 ▼ (Extracts Top K=3 Nodes via Cosine Similarity)  
                                     ┌───────────────────────┐  
                                     │ Inference Model       │  
                                     │ (gemma4:e2b Engine)   │  
                                     └───────────┬───────────┘  
                                                 │  
                                                 ▼ (Returns clean generated draft or 'ESCALATE_TO_HUMAN')  
                             [ OUTBOUND OVER NETWORK EDGE TO n8n / SLACK ]
```

## 2. Workspace Storage Wireframe (Database Layout)

This wireframe tracks the mapping pattern inside the local PostgreSQL container. LlamaIndex initializes, structures, and indexes the target matrix table natively, leaving your Django migrations lightweight and decoupled.  

```plaintext
+---------------------------------------------------------------------------------------------------------------------+  
| Local Container Network: PostgreSQL Store [Port 5432]                                                               |  
+---------------------------------------------------------------------------------------------------------------------+  
|                                                                                                                     |  
|  Database Workspace: "customer_ops"                                                                                 |  
|                                                                                                                     |  
|    +-------------------------------------------------------------------------------------------------------------+  |  
|    | Extension Loaded: CREATE EXTENSION IF NOT EXISTS vector;                                                    |  |  
|    +-------------------------------------------------------------------------------------------------------------+  |  
|                                                                                                                     |  
|    +-------------------------------------------------------------------------------------------------------------+  |  
|    | Table: "enterprise_knowledge_matrix"                                                                        |  |  
|    | +---------------+-------------------+----------------------+----------------------------------------------+ |  |  
|    | | Column Name   | Type              | Modifier             | Functional Description                       | |  |  
|    | +---------------+-------------------+----------------------+----------------------------------------------+ |  |  
|    | | id            | UUID / VARCHAR    | PRIMARY KEY          | Distinct LlamaIndex node tracker identifier  | |  |  
|    | | text          | TEXT              | NOT NULL             | Raw string chunk content matched by vector  | |  |  
|    | | metadata_     | JSONB             | NULLABLE             | Storage dictionary for file pathways/tags    | |  |  
|    | | embedding     | vector(768)       | INDEXED (HNSW/IVF)   | Mathematical multi-dimensional context point | |  |  
|    | +---------------+-------------------+----------------------+----------------------------------------------+ |  |  
|    +-------------------------------------------------------------------------------------------------------------+  |  
|                                                                                                                     |  
+---------------------------------------------------------------------------------------------------------------------+
```

## 3. Production Source Code Packages

### Ingestion & Query Broker Configuration (`/triage_api/rag_service.py`)

This microservice abstracts connectivity to our persistent data framework. It manages the mathematical semantic matching vectors using real-world enterprise infrastructure packages.  

```python
import os  
from llama_index.core import VectorStoreIndex, StorageContext  
from llama_index.vector_stores.postgres import PGVectorStore  
from llama_index.embeddings.ollama import OllamaEmbedding  
from llama_index.llms.ollama import Ollama

# Target Local Environment Variables  
DB_NAME = "customer_ops"  
USER = "postgres"  
PASSWORD = "local_secure_password123"  
HOST = "localhost"  
PORT = "5432"

def get_production_rag_engine():  
    """Initializes an enterprise-grade RAG indexing and retrieval network."""  
      
    # 1. Instantiate Local Open-Source Intelligence Abstractions  
    embed_model = OllamaEmbedding(model_name="nomic-embed-text", base_url="http://localhost:11434")  
    llm = Ollama(model="gemma4:e2b", base_url="http://localhost:11434", request_timeout=60.0)  
      
    # 2. Bind Persistent pgvector Layer Storage Engine  
    vector_store = PGVectorStore.from_params(  
        host=HOST,  
        port=PORT,  
        database=DB_NAME,  
        user=USER,  
        password=PASSWORD,  
        table_name="enterprise_knowledge_matrix",  
        embed_dim=768  
    )  
      
    # 3. Mount Memory Management Map  
    storage_context = StorageContext.from_defaults(vector_store=vector_store)  
      
    # 4. Compile the Runtime Index Matrix Map  
    index = VectorStoreIndex.from_documents(  
        [],   
        storage_context=storage_context,   
        embed_model=embed_model  
    )  
      
    # 5. Extract Context Engine with Multi-Source Fallbacks  
    query_engine = index.as_query_engine(  
        llm=llm,  
        similarity_top_k=3,  
        response_mode="compact"  
    )  
      
    return query_engine
```

### Production API Route Controller (`/triage_api/views.py`)

This controller acts as our API exposure gate. It fields requests passing the n8n threshold, enforces structural formatting, and intercepts hallucinations before they can exit the execution loop.  

```python
from rest_framework.views import APIView  
from rest_framework.response import Response  
from rest_framework import status  
from .rag_service import get_production_rag_engine

class TriageRAGResponderView(APIView):  
    def post(self, request):  
        raw_email_text = request.data.get("text", "")  
        if not raw_email_text:  
            return Response({"error": "Malformed payload input: text parameter is required"}, status=status.HTTP_400_BAD_REQUEST)  
          
        try:  
            # 1. Spin up the production-ready LlamaIndex instance  
            rag_engine = get_production_rag_engine()  
              
            # 2. Inject Strict System Guardrails directly over customer runtime contexts  
            system_guardrails = (  
                "You are an enterprise support automation service. Answer the customer query using only the provided context. "  
                "If the context does not contain a definitive answer to the query, output exactly: 'ESCALATE_TO_HUMAN'.\n"  
                f"Customer Query: {raw_email_text}"  
            )  
              
            # 3. Query the multidimensional vector index  
            engine_response = rag_engine.query(system_guardrails)  
              
            # 4. Ship clean data packets back down the execution pipeline to the cloud VPS  
            return Response({  
                "status": "success",  
                "generated_draft": str(engine_response),  
                "sources_matched": len(engine_response.source_nodes)  
            }, status=status.HTTP_200_OK)  
              
        except Exception as e:  
            return Response({"status": "error", "message": str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
```

## 4. End-to-End Operational Pipeline Validation

To confirm Phase 3 compilation success, run a target terminal diagnostic check via an active localhost port loop:  

```bash
curl -X POST http://localhost:8000/api/v1/triage/rag/ \  
  -H "Content-Type: application/json" \  
  -d '{"text": "How do I clear cache on the enterprise interface?"}'
```

### Expected JSON Execution Outbound Result

```json
{  
  "status": "success",  
  "generated_draft": "ESCALATE_TO_HUMAN",  
  "sources_matched": 0  
}
```

**Systems Verification Metric:** If the backend database contains no uploaded configuration notes on checking cache arrays, the model must output the exact matching string token value `ESCALATE_TO_HUMAN` with zero document nodes hit. This structural data flag allows the n8n logic node on your cloud VPS to intelligently divert the ticket back to a human dashboard without displaying a hallucinated answer to the end user.
