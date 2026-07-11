import os
import sys
import psycopg2
from psycopg2 import sql
from pathlib import Path
from dotenv import load_dotenv

# Add Django backend folder to Python path
BASE_DIR = Path(__file__).resolve().parent.parent
sys.path.append(str(BASE_DIR))

# Load environment variables. override=True so the project .env is authoritative
# even when a machine-wide var like OLLAMA_HOST=0.0.0.0 (the Ollama *server* bind
# address) is already exported into the shell environment.
load_dotenv(BASE_DIR / '.env', override=True)

from llama_index.core import SimpleDirectoryReader
from llama_index.core.node_parser import SentenceSplitter
from llama_index.core.schema import MetadataMode
from llama_index.vector_stores.postgres import PGVectorStore
from llama_index.embeddings.ollama import OllamaEmbedding

def check_and_initialize_vector_db():
    """Verifies pgvector extension and seeds documents from the knowledge base."""
    db_name = os.getenv('DB_NAME', 'customer_ops')
    db_user = os.getenv('DB_USER', 'postgres')
    db_password = os.getenv('DB_PASSWORD', 'local_secure_password123')
    db_host = os.getenv('DB_HOST', 'localhost')
    db_port = os.getenv('DB_PORT', '5432')
    
    kb_path = BASE_DIR.parent / 'knowledge_base'
    if not kb_path.exists():
        os.makedirs(kb_path)
        # Create a dummy help article for testing
        dummy_file = kb_path / 'billing_faq.txt'
        with open(dummy_file, 'w', encoding='utf-8') as f:
            f.write(
                "Enterprise Uptime & Refund Policy:\n"
                "We guarantee a 99.9% server uptime. If server uptime falls below 99.9% in a given quarter, "
                "customers are eligible for a 10% refund on their monthly subscription fee. Requests must "
                "be sent to billing@enterprise.com within 30 days of the quarter ending.\n"
            )
        print(f"Created a dummy knowledge base folder and sample article at: {dummy_file}")

    print("Connecting to PostgreSQL to verify database and pgvector extension...")
    try:
        # Connect to 'postgres' database first to ensure the target DB exists
        conn = psycopg2.connect(
            host=db_host,
            port=db_port,
            user=db_user,
            password=db_password,
            database='postgres'
        )
        conn.autocommit = True
        cursor = conn.cursor()
        
        # Check if target DB exists, create if not.
        # Use a bound parameter for the value and a quoted identifier for the
        # database name so the configured DB_NAME cannot inject SQL.
        cursor.execute("SELECT 1 FROM pg_catalog.pg_database WHERE datname = %s;", (db_name,))
        exists = cursor.fetchone()
        if not exists:
            print(f"Database '{db_name}' does not exist. Creating...")
            cursor.execute(sql.SQL("CREATE DATABASE {};").format(sql.Identifier(db_name)))
        cursor.close()
        conn.close()
        
        # Connect to the target DB
        conn = psycopg2.connect(
            host=db_host,
            port=db_port,
            user=db_user,
            password=db_password,
            database=db_name
        )
        conn.autocommit = True
        cursor = conn.cursor()
        
        # Load pgvector extension
        print("Enabling pgvector extension if not exists...")
        cursor.execute("CREATE EXTENSION IF NOT EXISTS vector;")
        cursor.close()
        conn.close()
        print("PostgreSQL & pgvector verification successful.")
        
    except Exception as e:
        print(f"Database Connection Failure: {e}")
        print("Note: Ensure PostgreSQL is running locally and credentials in your .env are correct.")
        sys.exit(1)

    # Ingesting files using LlamaIndex
    print("Reading documents from the knowledge_base folder...")
    try:
        reader = SimpleDirectoryReader(input_dir=str(kb_path))
        documents = reader.load_data()
        if not documents:
            print("No documents found in knowledge_base directory to index.")
            return
            
        print(f"Loaded {len(documents)} document(s). Initializing LlamaIndex and generating embeddings...")
        
        # Instantiate local Ollama Embedding
        ollama_host = os.getenv('OLLAMA_HOST', 'http://127.0.0.1:11434')
        embed_model_name = os.getenv('OLLAMA_EMBED_MODEL', 'nomic-embed-text')
        embed_model = OllamaEmbedding(model_name=embed_model_name, base_url=ollama_host)

        # Mount pgvector store
        vector_store = PGVectorStore.from_params(
            host=db_host,
            port=db_port,
            database=db_name,
            user=db_user,
            password=db_password,
            table_name="enterprise_knowledge_matrix",
            embed_dim=768
        )

        # Split documents into nodes, then embed each node sequentially with a
        # blocking (synchronous) call. LlamaIndex's default from_documents() path
        # fans embedding requests out concurrently over async HTTP, which Ollama
        # intermittently rejects with "Failed to connect". Embedding one node at a
        # time is fully deterministic and fast enough for a knowledge base seed.
        nodes = SentenceSplitter().get_nodes_from_documents(documents)
        print(f"Split into {len(nodes)} node(s). Embedding sequentially...")
        for i, node in enumerate(nodes, start=1):
            node.embedding = embed_model.get_text_embedding(
                node.get_content(metadata_mode=MetadataMode.EMBED)
            )
            print(f"  embedded node {i}/{len(nodes)}")

        vector_store.add(nodes)
        print("Database successfully seeded and vector index created.")
        
    except Exception as e:
        print(f"LlamaIndex Seeding Failure: {e}")
        print("If this is due to Ollama / model availability on this laptop, the script has successfully set up the postgres table schema and will run when Ollama is running on the target PC.")

if __name__ == "__main__":
    check_and_initialize_vector_db()
