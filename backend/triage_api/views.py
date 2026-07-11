from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from .rag_service import get_production_rag_engine

class TriageRAGResponderView(APIView):
    """
    API View to interface with the LlamaIndex pgvector RAG system.
    Receives incoming tickets parsed by n8n and returns automated draft answers.
    """
    def post(self, request):
        raw_email_text = request.data.get("text", "")
        if not raw_email_text:
            return Response(
                {"error": "Malformed payload input: 'text' parameter is required"}, 
                status=status.HTTP_400_BAD_REQUEST
            )
        
        try:
            # 1. Spin up the production LlamaIndex RAG engine
            rag_engine = get_production_rag_engine()
            
            # 2. Inject strict system guardrails directly over customer queries
            system_guardrails = (
                "You are an enterprise support automation service. Answer the customer query using only the provided context. "
                "If the context does not contain a definitive answer to the query, output exactly: 'ESCALATE_TO_HUMAN'.\n"
                f"Customer Query: {raw_email_text}"
            )
            
            # 3. Query the vector index
            engine_response = rag_engine.query(system_guardrails)
            
            # 4. Return the generated draft and matched sources metadata
            return Response({
                "status": "success",
                "generated_draft": str(engine_response),
                "sources_matched": len(getattr(engine_response, "source_nodes", []))
            }, status=status.HTTP_200_OK)
            
        except Exception as e:
            # Provide descriptive errors in case the database/Ollama is not yet running on this laptop
            return Response({
                "status": "error",
                "message": (
                    f"RAG Engine Query Failure: {str(e)}. "
                    "Note: Ensure PostgreSQL (with pgvector) and Ollama are active and the configured models are pulled."
                )
            }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
