import os
from llama_index.core import VectorStoreIndex, StorageContext
from llama_index.vector_stores.postgres import PGVectorStore
from llama_index.embeddings.ollama import OllamaEmbedding
from llama_index.llms.ollama import Ollama

def get_production_rag_engine():
    """Initializes the RAG indexing and retrieval system using environment variables."""
    
    # 1. Fetch configurations from environment variables
    ollama_host = os.getenv('OLLAMA_HOST', 'http://localhost:11434')
    llm_model = os.getenv('OLLAMA_LLM_MODEL', 'gemma4:e2b')
    embed_model_name = os.getenv('OLLAMA_EMBED_MODEL', 'nomic-embed-text')
    
    db_name = os.getenv('DB_NAME', 'customer_ops')
    db_user = os.getenv('DB_USER', 'postgres')
    db_password = os.getenv('DB_PASSWORD', 'local_secure_password123')
    db_host = os.getenv('DB_HOST', 'localhost')
    db_port = os.getenv('DB_PORT', '5432')

    # Ollama serializes requests per model; when n8n's Classifier + Risk Assessor
    # and this RAG call all hit gemma4:e2b at once (plus a possible cold model
    # reload ~11s), 60s is too tight. Allow a generous, env-tunable timeout that
    # still stays under the n8n HTTP node's 300s ceiling.
    ollama_timeout = float(os.getenv('OLLAMA_REQUEST_TIMEOUT', '180'))

    # 2. Instantiate Local Open-Source Intelligence Abstractions
    embed_model = OllamaEmbedding(model_name=embed_model_name, base_url=ollama_host, embed_batch_size=1, request_timeout=ollama_timeout)
    llm = Ollama(model=llm_model, base_url=ollama_host, request_timeout=ollama_timeout)
    
    # 3. Bind Persistent pgvector Layer Storage Engine
    vector_store = PGVectorStore.from_params(
        host=db_host,
        port=db_port,
        database=db_name,
        user=db_user,
        password=db_password,
        table_name="enterprise_knowledge_matrix",
        embed_dim=768
    )
    
    # 4. Mount Memory Management Map
    storage_context = StorageContext.from_defaults(vector_store=vector_store)
    
    # 5. Compile the Runtime Index Matrix Map
    # During initialization, we load an empty document list as a entry point.
    index = VectorStoreIndex.from_documents(
        [], 
        storage_context=storage_context, 
        embed_model=embed_model
    )
    
    # 6. Extract Query Engine with top_k retrieval and compact fallback
    query_engine = index.as_query_engine(
        llm=llm,
        similarity_top_k=3,
        response_mode="compact"
    )
    
    return query_engine
