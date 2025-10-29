# AGENTS.md - QSystem Development Guide

This file provides comprehensive guidance to Claude Code (claude.ai/code) when working with the QSystem codebase.

## 🚀 Quick Start Commands

### ⚠️ IMPORTANTE: Desarrollo SOLO con Docker

**SIEMPRE usa Docker para desarrollo. NO ejecutes servidores locales.**

**¿Por qué?**
- ✅ El contenedor `frontend-dev` tiene **hot reload configurado** (detecta cambios automáticamente)
- ✅ El archivo `.env` está en la raíz y Docker lo lee correctamente
- ✅ Evita conflictos de puertos y configuración inconsistente
- ❌ `npm run dev` local NO lee el `.env` de la raíz correctamente

### Most Used Development Commands
```bash
# Start everything with hot reload (COMANDO PRINCIPAL)
docker-compose --profile dev up -d

# Ver estado de contenedores
docker-compose ps

# Ver logs en tiempo real (útil para debugging)
docker-compose logs -f backend
docker-compose logs -f frontend-dev

# Detener todos los servicios
docker-compose down

# Run Django migrations
docker-compose exec backend python manage.py migrate

# Create Django superuser
docker-compose exec backend python manage.py createsuperuser

# Django shell for debugging
docker-compose exec backend python manage.py shell

# Run tests (dentro de contenedor)
docker-compose exec backend python manage.py test apps.core -v 2

# Lint & format frontend
cd qsystem-frontend && npm run lint
```

### Puertos de Desarrollo
- **Frontend Dev (Vite)**: http://localhost:5173 (con hot reload)
- **Backend (Django)**: http://localhost:8003
- **Base de datos (PostgreSQL)**: localhost:5432

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────┐
│                   Frontend (React)               │
│  - Vite dev server (port 5173)                  │
│  - JWT tokens in HttpOnly cookies               │
│  - Context providers for state                  │
└────────────────┬────────────────────────────────┘
                 │ HTTPS/REST API
┌────────────────▼────────────────────────────────┐
│              Backend (Django REST)              │
│  - Port 8003 (Docker) / 8000 (local)           │
│  - JWT authentication                          │
│  - Soft deletes & audit trail                  │
└────────────────┬────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────┐
│           PostgreSQL 15 Database                │
│  - Soft deletes via deleted_date               │
│  - History tracking with simple-history        │
└─────────────────────────────────────────────────┘
```

## 💻 Development Workflows

### Adding a New Feature End-to-End

1. **Backend Model** (if needed):
```python
# In qsystem-backend/src/apps/[app_name]/models.py
from src.apps.core.models import BaseModel  # Includes soft delete

class YourModel(BaseModel):
    name = models.CharField(max_length=255)
    # BaseModel provides: id, deleted_date, created_at, updated_at

    objects = ActiveManager()  # Excludes soft deleted
    all_objects = models.Manager()  # Includes all

    class Meta:
        db_table = 'your_model'
        verbose_name = 'Your Model'
```

2. **Create Serializer**:
```python
# In qsystem-backend/src/apps/[app_name]/serializers.py
from rest_framework import serializers
from .models import YourModel

class YourModelSerializer(serializers.ModelSerializer):
    # Add computed fields
    display_name = serializers.SerializerMethodField()

    class Meta:
        model = YourModel
        fields = '__all__'
        read_only_fields = ('id', 'created_at', 'updated_at')

    def get_display_name(self, obj):
        return f"{obj.name} - {obj.id}"

    def validate_name(self, value):
        if YourModel.objects.filter(name=value).exists():
            raise serializers.ValidationError("Name must be unique")
        return value
```

3. **Create ViewSet**:
```python
# In qsystem-backend/src/apps/[app_name]/views.py
from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from .models import YourModel
from .serializers import YourModelSerializer

class YourModelViewSet(viewsets.ModelViewSet):
    queryset = YourModel.objects.all()
    serializer_class = YourModelSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        qs = super().get_queryset()
        # Add filters based on user role
        if self.request.user.role == 'customer':
            qs = qs.filter(user=self.request.user)
        return qs

    @action(detail=True, methods=['post'])
    def custom_action(self, request, pk=None):
        instance = self.get_object()
        # Custom logic
        return Response({'status': 'success'})
```

4. **Register URL**:
```python
# In qsystem-backend/src/apps/[app_name]/urls.py
from rest_framework.routers import DefaultRouter
from .views import YourModelViewSet

router = DefaultRouter()
router.register('your-models', YourModelViewSet)

urlpatterns = router.urls
```

5. **Frontend API Service**:
```javascript
// In qsystem-frontend/src/api/yourModule.jsx
import axios from './axios';

export const yourModelAPI = {
  list: (params = {}) => axios.get('/your-module/your-models/', { params }),
  get: (id) => axios.get(`/your-module/your-models/${id}/`),
  create: (data) => axios.post('/your-module/your-models/', data),
  update: (id, data) => axios.put(`/your-module/your-models/${id}/`, data),
  delete: (id) => axios.delete(`/your-module/your-models/${id}/`),
  customAction: (id) => axios.post(`/your-module/your-models/${id}/custom_action/`),
};
```

6. **React Component**:
```jsx
// In qsystem-frontend/src/components/YourComponent.jsx
import { useState, useEffect } from 'react';
import { yourModelAPI } from '@/api/yourModule';
import { toast } from 'react-toastify';

export default function YourComponent() {
  const [data, setData] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    loadData();
  }, []);

  const loadData = async () => {
    try {
      setLoading(true);
      const response = await yourModelAPI.list();
      setData(response.data.results || response.data);
    } catch (error) {
      toast.error('Error loading data');
      console.error(error);
    } finally {
      setLoading(false);
    }
  };

  const handleCreate = async (formData) => {
    try {
      await yourModelAPI.create(formData);
      toast.success('Created successfully');
      loadData();
    } catch (error) {
      toast.error(error.response?.data?.detail || 'Error creating');
    }
  };

  return (
    <div>
      {/* Your UI here */}
    </div>
  );
}
```

### Creating Forms with Validation

```jsx
// Standard form pattern with validation
import { useState } from 'react';
import { Form, Button, Card } from 'react-bootstrap';

export default function YourForm({ onSubmit, initialData = {} }) {
  const [formData, setFormData] = useState(initialData);
  const [errors, setErrors] = useState({});
  const [submitting, setSubmitting] = useState(false);

  const validateForm = () => {
    const newErrors = {};

    if (!formData.name?.trim()) {
      newErrors.name = 'Name is required';
    }

    if (formData.email && !/\S+@\S+\.\S+/.test(formData.email)) {
      newErrors.email = 'Invalid email format';
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleSubmit = async (e) => {
    e.preventDefault();

    if (!validateForm()) return;

    setSubmitting(true);
    try {
      await onSubmit(formData);
    } finally {
      setSubmitting(false);
    }
  };

  const handleChange = (e) => {
    const { name, value, type, checked } = e.target;
    setFormData(prev => ({
      ...prev,
      [name]: type === 'checkbox' ? checked : value
    }));
    // Clear error for this field
    if (errors[name]) {
      setErrors(prev => ({ ...prev, [name]: null }));
    }
  };

  return (
    <Form onSubmit={handleSubmit}>
      <Form.Group className="mb-3">
        <Form.Label>Name *</Form.Label>
        <Form.Control
          type="text"
          name="name"
          value={formData.name || ''}
          onChange={handleChange}
          isInvalid={!!errors.name}
          required
        />
        <Form.Control.Feedback type="invalid">
          {errors.name}
        </Form.Control.Feedback>
      </Form.Group>

      <Button type="submit" disabled={submitting}>
        {submitting ? 'Saving...' : 'Save'}
      </Button>
    </Form>
  );
}
```

## ⚙️ Configuration Guide

### Required Environment Variables

```bash
# .env file in project root

# === Django Core ===
SECRET_KEY=your-secret-key-here  # Generate with: python -c "from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())"
DEBUG=True  # Set to False in production
ALLOWED_HOSTS=localhost,127.0.0.1,backend

# === Database (both formats needed for compatibility) ===
DB_NAME=qsystem
DB_USER=postgres
DB_PASSWORD=postgres
DB_HOST=db  # Use 'localhost' for local development
DB_PORT=5432

POSTGRES_DB=qsystem
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres

# === CORS Configuration ===
CORS_ALLOWED_ORIGINS=http://localhost:3000,http://localhost:5173,http://127.0.0.1:3000,http://127.0.0.1:5173

# === Frontend ===
VITE_API_URL=http://localhost:8003/api  # MUST include /api

# === Email Configuration (Optional) ===
EMAIL_BACKEND=django.core.mail.backends.smtp.EmailBackend
EMAIL_HOST=smtp.gmail.com
EMAIL_PORT=587
EMAIL_USE_TLS=True
EMAIL_HOST_USER=your-email@gmail.com
EMAIL_HOST_PASSWORD=your-app-password  # Use app-specific password
DEFAULT_FROM_EMAIL=noreply@qsystem.com
EMAIL_TIMEOUT=30

# === Microsoft Graph API (Optional - for advanced email features) ===
AZURE_CLIENT_ID=your-client-id
AZURE_CLIENT_SECRET=your-client-secret
AZURE_TENANT_ID=your-tenant-id

# === AWS S3 Storage (Optional) ===
USE_S3=False  # Set to True to enable S3
AWS_ACCESS_KEY_ID=your-key
AWS_SECRET_ACCESS_KEY=your-secret
AWS_STORAGE_BUCKET_NAME=your-bucket
AWS_S3_REGION_NAME=us-east-1
AWS_S3_CUSTOM_DOMAIN=  # Optional CloudFront domain
AWS_CLOUDFRONT_KEY_ID=  # Optional CloudFront signing
AWS_CLOUDFRONT_KEY=  # Optional CloudFront private key
```

## 🎨 Frontend Patterns

### Context Providers

The app uses several React contexts for state management:

```jsx
// Available contexts in qsystem-frontend/src/contexts/

// 1. AuthContext - User authentication state
import { useAuth } from '@/hooks/useAuth';
const { user, login, logout, isAuthenticated } = useAuth();

// 2. QuotationContext - Active quotation management
import { useQuotation } from '@/contexts/QuotationContext';
const { quotation, updateQuotation, clearQuotation } = useQuotation();

// 3. TrashModeContext - Soft delete UI mode
import { useTrashMode } from '@/contexts/TrashModeContext';
const { trashMode, setTrashMode } = useTrashMode();

// 4. ThemeContext - UI theme management
import { useTheme } from '@/contexts/ThemeContext';
const { theme, toggleTheme } = useTheme();
```

### Custom Hooks

```jsx
// Debounced search
import { useDebounce } from '@/hooks/useDebounce';
const debouncedSearchTerm = useDebounce(searchTerm, 500);

// Responsive breakpoints
import { useBreakpoint } from '@/hooks/useBreakpoint';
const { isMobile, isTablet, isDesktop } = useBreakpoint();

// API fetching with loading state
import { useFetch } from '@/hooks/useFetch';
const { data, loading, error, refetch } = useFetch('/api/endpoint');

// Instructor availability checker
import { useInstructorAvailability } from '@/hooks/useInstructorAvailability';
const { checkAvailability, conflicts } = useInstructorAvailability();
```

### Component File Structure

```
src/components/
├── dashboard/       # Dashboard-specific components
├── forms/          # Reusable form components
├── layout/         # Layout components (Header, Footer, Sidebar)
├── modals/         # Modal dialog components
├── pages/          # Page-specific components
├── pdf/            # PDF generation components
├── tables/         # Data table components
└── ui/             # Generic UI components
```

## 🔐 Authentication & Security

### JWT Authentication Flow

```
1. User login → POST /api/auth/login/
2. Backend returns JWT tokens in HttpOnly cookies:
   - access_token (15 min lifetime)
   - refresh_token (7 days lifetime)
3. Axios interceptor auto-refreshes on 401
4. Logout clears cookies → POST /api/auth/logout/
```

### User Roles & Permissions

```python
# Three user roles with different access levels:
ROLE_CHOICES = [
    ("admin", "Administrador"),    # Full system access
    ("seller", "Vendedor"),        # Sales & quotations
    ("customer", "Cliente"),       # View own courses
]

# Check role in views:
if request.user.role == 'admin':
    # Admin logic
elif request.user.role == 'seller':
    # Seller logic
else:
    # Customer logic
```

### Protected Routes in Frontend

```jsx
// Routes are protected by role
<ProtectedRoute allowedRoles={['admin', 'seller']}>
  <YourComponent />
</ProtectedRoute>

// Automatic redirects by role:
// admin → /dashboard
// seller → /cotizaciones
// customer → /mis-cursos
```

## 📊 Business Logic

### Pricing Calculation System

```python
# Complex pricing in CursoAgendado model
def calculate_precio(self):
    """
    Price factors:
    1. Base price from course catalog
    2. Location multiplier (on-site vs online)
    3. Duration adjustment
    4. Custom discounts
    5. Plaza-specific pricing
    """
    base_price = self.curso.precio_base

    # Location factor
    if self.modalidad == 'online':
        base_price *= 0.8  # 20% discount for online

    # Duration factor
    duration_hours = self.calculate_duration()
    if duration_hours > 8:
        base_price *= 1.2  # 20% increase for multi-day

    return base_price
```

### Instructor Availability System

```python
# Two-level availability:
# 1. Regular weekly schedule (DisponibilidadInstructor)
# 2. Specific date blocks (BloqueDisponibilidad)

# Check availability:
def is_instructor_available(instructor, date, start_time, end_time):
    # Check regular schedule
    weekday = date.weekday()
    regular = DisponibilidadInstructor.objects.filter(
        instructor=instructor,
        dia_semana=weekday,
        hora_inicio__lte=start_time,
        hora_fin__gte=end_time
    ).exists()

    # Check specific blocks
    blocked = BloqueDisponibilidad.objects.filter(
        instructor=instructor,
        fecha=date,
        tipo='bloqueado'
    ).exists()

    return regular and not blocked
```

### Quotation Workflow

```python
# Unified quotation model: CotizacionCerrada
# Line items: PartidaCotizacion

# Status flow:
ESTADO_CHOICES = [
    ('borrador', 'Borrador'),      # Initial state
    ('enviada', 'Enviada'),        # Sent to customer
    ('aceptada', 'Aceptada'),      # Customer accepted
    ('rechazada', 'Rechazada'),    # Customer rejected
    ('vencida', 'Vencida'),        # Expired
]
```

## 🐛 Common Issues & Solutions

### CORS Errors
```bash
# Check CORS_ALLOWED_ORIGINS includes your frontend URL
# Frontend must use withCredentials: true for cookies
# Verify VITE_API_URL ends with /api
```

### JWT Token Issues
```javascript
// Tokens not refreshing? Check axios interceptor:
// qsystem-frontend/src/api/axios.jsx
// Ensure refresh endpoint is excluded from retry logic
```

### Soft Delete Gotchas
```python
# Always use .objects (not .all_objects) for queries
Model.objects.all()  # Excludes deleted
Model.all_objects.all()  # Includes deleted

# To restore deleted:
instance.deleted_date = None
instance.save()
```

### Date/Time Format Issues
```javascript
// Always use ISO format for backend
const isoDate = new Date().toISOString().split('T')[0];  // YYYY-MM-DD
const isoTime = '14:30:00';  // HH:MM:SS

// Parse backend dates
const date = new Date(backendDate);
```

### Migration Conflicts
```bash
# If migrations conflict:
python manage.py showmigrations [app_name]
python manage.py migrate [app_name] [migration_name] --fake
python manage.py makemigrations --merge
```

## 🧪 Testing

### Backend Testing

```bash
# Run all tests
python manage.py test

# Run specific app tests
python manage.py test apps.core -v 2

# Run specific test class
python manage.py test apps.core.tests.TestCliente

# Run with coverage
pip install coverage
coverage run --source='.' manage.py test
coverage report
```

### Test Examples

```python
# qsystem-backend/src/apps/core/tests.py
from django.test import TestCase
from rest_framework.test import APITestCase
from django.contrib.auth import get_user_model

User = get_user_model()

class YourModelTestCase(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            username='test',
            email='test@test.com',
            password='test123'
        )

    def test_create_model(self):
        # Your test logic
        pass

class YourAPITestCase(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            username='test',
            email='test@test.com',
            password='test123'
        )
        self.client.force_authenticate(user=self.user)

    def test_list_endpoint(self):
        response = self.client.get('/api/your-endpoint/')
        self.assertEqual(response.status_code, 200)
```

### Frontend Testing

```bash
# Run tests
cd qsystem-frontend
npm test

# Run with coverage
npm test -- --coverage
```

## 📚 Specialized Components

### DateTimeSelector Component

Advanced date/time selector with 4 modes:

```jsx
import DateTimeSelector from '@/components/ui/DateTimeSelector';

// Mode 1: Single date
<DateTimeSelector
  mode="single"
  value={{ date: '2024-01-20', startTime: '09:00', endTime: '17:00' }}
  onChange={(value) => console.log(value)}
/>

// Mode 2: Date range
<DateTimeSelector
  mode="range"
  value={{ startDate: '2024-01-20', endDate: '2024-01-22', ... }}
/>

// Mode 3: Multiple dates
<DateTimeSelector
  mode="multiple"
  value={[
    { date: '2024-01-20', startTime: '09:00', endTime: '12:00' },
    { date: '2024-01-21', startTime: '14:00', endTime: '18:00' }
  ]}
/>

// Mode 4: Recurring
<DateTimeSelector
  mode="recurring"
  value={{ daysOfWeek: [1, 3, 5], startTime: '09:00', endTime: '17:00' }}
/>
```

### Import System

Bulk import via CSV/Excel:

```python
# Process imports command
python manage.py process_imports

# Import job model tracks status:
ESTADO_CHOICES = [
    ('pendiente', 'Pending'),
    ('procesando', 'Processing'),
    ('completado', 'Completed'),
    ('error', 'Error'),
]
```

## 📝 Database Patterns

### Soft Deletes Implementation

```python
# BaseModel provides soft delete functionality
class BaseModel(models.Model):
    deleted_date = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    objects = ActiveManager()  # Default manager excludes deleted
    all_objects = models.Manager()  # Includes deleted

    class Meta:
        abstract = True

    def delete(self, using=None, keep_parents=False):
        """Soft delete by setting deleted_date"""
        self.deleted_date = timezone.now()
        self.save()

    def hard_delete(self):
        """Actually delete from database"""
        super().delete()

    def restore(self):
        """Restore soft deleted object"""
        self.deleted_date = None
        self.save()
```

### Audit Trail with History

```python
# Models automatically track changes
from simple_history.models import HistoricalRecords

class YourModel(BaseModel):
    history = HistoricalRecords()

# Access history:
instance.history.all()  # All changes
instance.history.most_recent()  # Latest version
instance.history.as_of(datetime)  # Version at specific time
```

### Complex Queries Examples

```python
# Filter with related models
from django.db.models import Q, Count, Sum

# Courses with available instructors
CursoAgendado.objects.filter(
    instructores__disponibilidad__dia_semana=1,
    fecha_inicio__gte=timezone.now()
).distinct()

# Quotations with totals
CotizacionCerrada.objects.annotate(
    total_items=Count('partidas'),
    total_amount=Sum('partidas__subtotal')
).filter(total_amount__gt=10000)

# Soft deleted in date range
Model.all_objects.filter(
    deleted_date__range=[start_date, end_date]
)
```

## 🔧 Utility Functions

### Common Django ORM Patterns

```python
# Bulk create with update
Model.objects.bulk_create(
    [Model(field=value) for value in values],
    update_conflicts=True,
    update_fields=['field'],
    unique_fields=['id']
)

# Select for update (lock rows)
with transaction.atomic():
    obj = Model.objects.select_for_update().get(pk=1)
    obj.field = new_value
    obj.save()

# Prefetch related to avoid N+1
queryset = Model.objects.prefetch_related(
    'related_model__nested_related'
)
```

### React Patterns

```jsx
// Error boundary component
class ErrorBoundary extends React.Component {
  state = { hasError: false };

  static getDerivedStateFromError(error) {
    return { hasError: true };
  }

  componentDidCatch(error, errorInfo) {
    console.error('Error caught:', error, errorInfo);
  }

  render() {
    if (this.state.hasError) {
      return <h1>Something went wrong.</h1>;
    }
    return this.props.children;
  }
}

// Lazy load components
const LazyComponent = React.lazy(() => import('./HeavyComponent'));

// Use with Suspense
<Suspense fallback={<div>Loading...</div>}>
  <LazyComponent />
</Suspense>
```

## 📌 Important Notes

### Performance Considerations

- Use `select_related()` for ForeignKey/OneToOne
- Use `prefetch_related()` for ManyToMany/reverse ForeignKey
- Implement pagination for large datasets
- Use database indexes on frequently queried fields
- Cache expensive computations

### Security Best Practices

- Never store sensitive data in frontend
- Always validate on backend, not just frontend
- Use Django's ORM to prevent SQL injection
- Implement rate limiting on sensitive endpoints
- Keep SECRET_KEY secure and rotate periodically
- Use environment variables for all secrets

### Docker Tips

```bash
# Rebuild specific service
docker-compose build backend

# Remove all containers and volumes
docker-compose down -v

# Execute command in running container
docker-compose exec backend bash

# View real-time logs
docker-compose logs -f --tail=100 backend

# Clean up Docker system
docker system prune -a
```

### Git Workflow

```bash
# Feature branch workflow
git checkout -b feature/your-feature
# Make changes
git add .
git commit -m "feat: add new feature"
git push origin feature/your-feature
# Create pull request

# Commit message convention
# feat: new feature
# fix: bug fix
# docs: documentation
# style: formatting
# refactor: code restructuring
# test: adding tests
# chore: maintenance
```

## 🚨 Emergency Commands

```bash
# Database is locked or corrupted
docker-compose down -v
docker-compose up -d db
docker-compose exec db psql -U postgres -c "DROP DATABASE qsystem;"
docker-compose exec db psql -U postgres -c "CREATE DATABASE qsystem;"
docker-compose exec backend python manage.py migrate

# Frontend won't compile
cd qsystem-frontend
rm -rf node_modules package-lock.json
npm install
npm run dev

# Backend migrations broken
python manage.py showmigrations
python manage.py migrate [app_name] zero
python manage.py makemigrations [app_name]
python manage.py migrate

# Reset everything
docker-compose down -v
docker system prune -a
# Then rebuild from scratch
```

---

**Remember**: Always check existing patterns in the codebase before implementing new features. Consistency is key!