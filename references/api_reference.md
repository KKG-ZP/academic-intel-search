# Semantic Scholar API Reference

## Base URL

```
https://api.semanticscholar.org/graph/v1
```

## Authentication

```bash
# Optional but recommended
curl -H "x-api-key: YOUR_API_KEY" ...
```

## Rate Limits

- **With API Key**: 1 request/second, 5000 requests/5 minutes
- **Without API Key**: Shared pool, easily hit 429

## Endpoints

### 1. Paper Search

```
GET /paper/search
GET /paper/search/bulk
```

**Parameters:**
- `query`: Search query string
- `year`: Year range (e.g., "2023-", "2020-2023")
- `limit`: Results per page (max 100 for search, 1000 for bulk)
- `fields`: Comma-separated fields to return
- `offset`: Pagination offset (search only)
- `token`: Pagination token (bulk only)

**Available Fields:**
- `paperId`, `title`, `abstract`, `year`
- `authors`, `venue`, `journal`
- `citationCount`, `referenceCount`
- `externalIds` (DOI, ArXiv, PubMed, etc.)
- `url`, `fieldsOfStudy`
- `publicationTypes`, `publicationDate`
- `isOpenAccess`, `openAccessPdf`

**Example:**

```bash
curl "https://api.semanticscholar.org/graph/v1/paper/search/bulk?query=motor+imagery+BCI&year=2024-&limit=50&fields=title,year,authors,venue,citationCount,externalIds,url" \
  -H "x-api-key: YOUR_KEY"
```

### 2. Get Paper Details

```
GET /paper/{paperId}
```

**Example:**

```bash
curl "https://api.semanticscholar.org/graph/v1/paper/649def34f8be52c8b66281af98ae884c09aef38b?fields=title,year,authors,abstract,citationCount,references,citations" \
  -H "x-api-key: YOUR_KEY"
```

### 3. Author Information

```
GET /author/{authorId}
```

**Available Fields:**
- `authorId`, `name`, `aliases`
- `affiliations`, `homepage`, `url`
- `hIndex`, `citationCount`, `paperCount`
- `papers` (with nested fields)

**Example:**

```bash
curl "https://api.semanticscholar.org/graph/v1/author/1699545?fields=name,hIndex,citationCount,paperCount,affiliations" \
  -H "x-api-key: YOUR_KEY"
```

## Response Format

### Search Response

```json
{
  "total": 1234,
  "offset": 0,
  "next": 100,
  "data": [
    {
      "paperId": "649def34f8be52c8b66281af98ae884c09aef38b",
      "title": "Paper Title",
      "year": 2024,
      "authors": [
        {
          "authorId": "1699545",
          "name": "Author Name"
        }
      ],
      "venue": "IEEE TNSRE",
      "citationCount": 42,
      "externalIds": {
        "DOI": "10.1109/...",
        "ArXiv": "2401.12345"
      },
      "url": "https://www.semanticscholar.org/paper/..."
    }
  ]
}
```

### Bulk Search Response

```json
{
  "total": 1234,
  "token": "next_page_token",
  "data": [...]
}
```

## Error Codes

- `400`: Bad request (invalid parameters)
- `404`: Resource not found
- `429`: Rate limit exceeded
- `500`: Internal server error

## Best Practices

1. **Use API Key**: Significantly higher rate limits
2. **Use Bulk Search**: For large result sets (up to 1000/request)
3. **Implement Backoff**: Exponential backoff on 429 errors
4. **Cache Results**: Avoid redundant requests
5. **Specific Fields**: Only request needed fields to reduce response size

## Query Tips

### Boolean Operators

- `AND`: `motor imagery AND BCI`
- `OR`: `BCI OR brain-computer interface`
- `NOT`: `BCI NOT invasive`
- Quotes: `"motor imagery"` (exact phrase)

### Field-Specific Search

- `title:BCI`: Search in title only
- `author:Smith`: Search by author name
- `venue:TNSRE`: Search by venue

### Year Filtering

- `2024-`: 2024 and later
- `-2023`: 2023 and earlier
- `2020-2023`: Between 2020 and 2023

## Common Use Cases

### 1. Find Recent Papers in Specific Venue

```bash
curl "https://api.semanticscholar.org/graph/v1/paper/search?query=venue:TNSRE&year=2024-&limit=100&fields=title,year,citationCount,url"
```

### 2. Find Highly Cited Papers

```bash
# Search then filter by citationCount in your script
curl "https://api.semanticscholar.org/graph/v1/paper/search/bulk?query=motor+imagery&year=2020-&limit=1000&fields=title,year,citationCount" | \
jq '.data[] | select(.citationCount >= 100)'
```

### 3. Track Author's Recent Work

```bash
curl "https://api.semanticscholar.org/graph/v1/author/1699545?fields=papers.title,papers.year,papers.citationCount&limit=50"
```

## References

- Official API Docs: https://api.semanticscholar.org/api-docs/
- API Key Registration: https://www.semanticscholar.org/product/api
- OpenAPI Spec: https://api.semanticscholar.org/api-docs/graph
