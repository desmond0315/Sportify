import React, { useState, useEffect } from 'react';
import { collection, getDocs } from 'firebase/firestore';
import { db } from '../firebase';

const UserManagementPage = () => {
  const [allUsers, setAllUsers] = useState([]);
  const [filteredUsers, setFilteredUsers] = useState([]);
  const [isLoading, setIsLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [roleFilter, setRoleFilter] = useState('all');

  useEffect(() => {
    fetchAllUsers();
  }, []);

  useEffect(() => {
    filterUsers();
  }, [searchQuery, roleFilter, allUsers]);

  const fetchAllUsers = async () => {
    setIsLoading(true);
    try {
      const users = [];

      const usersSnapshot = await getDocs(collection(db, 'users'));
      usersSnapshot.forEach((doc) => {
        const userData = doc.data();
        users.push({
          id: doc.id,
          name: userData.name || userData.displayName || 'N/A',
          email: userData.email || 'N/A',
          role: userData.role || 'player',
          phone: userData.phone || userData.phoneNumber || 'N/A',
          createdAt: userData.createdAt,
          isActive: userData.isActive !== false
        });
      });

      const coachesSnapshot = await getDocs(collection(db, 'coaches'));
      coachesSnapshot.forEach((doc) => {
        const coachData = doc.data();
        users.push({
          id: doc.id,
          name: coachData.name || coachData.coachName || 'N/A',
          email: coachData.email || 'N/A',
          role: 'coach',
          phone: coachData.phone || coachData.phoneNumber || 'N/A',
          createdAt: coachData.createdAt,
          isActive: coachData.isActive !== false
        });
      });

      const venueOwnersSnapshot = await getDocs(collection(db, 'venue_owners'));
      venueOwnersSnapshot.forEach((doc) => {
        const ownerData = doc.data();
        users.push({
          id: doc.id,
          name: ownerData.ownerName || ownerData.name || 'N/A',
          email: ownerData.email || 'N/A',
          role: 'venue_owner',
          phone: ownerData.phone || 'N/A',
          createdAt: ownerData.createdAt,
          isActive: ownerData.isActive !== false
        });
      });

      users.sort((a, b) => {
        if (!a.createdAt) return 1;
        if (!b.createdAt) return -1;
        return b.createdAt.seconds - a.createdAt.seconds;
      });

      setAllUsers(users);
      setFilteredUsers(users);
    } catch (error) {
      console.error('Error fetching users:', error);
      alert('Failed to fetch users');
    } finally {
      setIsLoading(false);
    }
  };

  const filterUsers = () => {
    let filtered = [...allUsers];

    if (roleFilter !== 'all') {
      filtered = filtered.filter(user => user.role === roleFilter);
    }

    if (searchQuery.trim()) {
      const query = searchQuery.toLowerCase();
      filtered = filtered.filter(user => 
        user.name.toLowerCase().includes(query) ||
        user.email.toLowerCase().includes(query) ||
        user.role.toLowerCase().includes(query)
      );
    }

    setFilteredUsers(filtered);
  };

  const getRoleBadgeColor = (role) => {
    switch(role) {
      case 'coach':
        return { bg: '#fef3e2', text: '#ff6b35' };
      case 'venue_owner':
        return { bg: '#e0f2fe', text: '#0284c7' };
      case 'player':
        return { bg: '#f3e8ff', text: '#9333ea' };
      default:
        return { bg: '#f3f4f6', text: '#6b7280' };
    }
  };

  const getRoleDisplayName = (role) => {
    switch(role) {
      case 'venue_owner':
        return 'Venue Owner';
      case 'coach':
        return 'Coach';
      case 'player':
        return 'Player';
      default:
        return role;
    }
  };

  const formatDate = (timestamp) => {
    if (!timestamp) return 'N/A';
    try {
      const date = timestamp.toDate ? timestamp.toDate() : new Date(timestamp);
      return date.toLocaleDateString('en-US', { 
        year: 'numeric', 
        month: 'short', 
        day: 'numeric' 
      });
    } catch (error) {
      return 'N/A';
    }
  };

  const getRoleStats = () => {
    const stats = {
      all: allUsers.length,
      player: allUsers.filter(u => u.role === 'player').length,
      coach: allUsers.filter(u => u.role === 'coach').length,
      venue_owner: allUsers.filter(u => u.role === 'venue_owner').length
    };
    return stats;
  };

  const stats = getRoleStats();

  if (isLoading) {
    return (
      <div style={{ 
        display: 'flex', 
        justifyContent: 'center', 
        alignItems: 'center', 
        minHeight: '100vh',
        background: 'linear-gradient(135deg, #f8fafc 0%, #ede9fe 50%, #f8fafc 100%)',
        fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif'
      }}>
        <div style={{ textAlign: 'center' }}>
          <div style={{
            width: '56px',
            height: '56px',
            border: '4px solid #e9d5ff',
            borderTop: '4px solid #8b5cf6',
            borderRadius: '50%',
            animation: 'spin 0.8s linear infinite',
            margin: '0 auto 20px'
          }} />
          <p style={{ color: '#64748b', fontSize: '16px', fontWeight: '600' }}>Loading users...</p>
          <style>{`
            @keyframes spin {
              0% { transform: rotate(0deg); }
              100% { transform: rotate(360deg); }
            }
          `}</style>
        </div>
      </div>
    );
  }

  return (
    <div style={{
      fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
      padding: '32px',
      background: 'linear-gradient(135deg, #f8fafc 0%, #ede9fe 50%, #f8fafc 100%)',
      minHeight: '100vh'
    }}>
      <div style={{ marginBottom: '32px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '16px', marginBottom: '12px' }}>
          <div style={{
            width: '56px',
            height: '56px',
            background: 'linear-gradient(135deg, #8b5cf6 0%, #7c3aed 100%)',
            borderRadius: '16px',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            boxShadow: '0 10px 30px rgba(139, 92, 246, 0.3)'
          }}>
            <svg width="28" height="28" viewBox="0 0 24 24" fill="white">
              <path d="M16 11c1.66 0 2.99-1.34 2.99-3S17.66 5 16 5c-1.66 0-3 1.34-3 3s1.34 3 3 3zm-8 0c1.66 0 2.99-1.34 2.99-3S9.66 5 8 5C6.34 5 5 6.34 5 8s1.34 3 3 3zm0 2c-2.33 0-7 1.17-7 3.5V19h14v-2.5c0-2.33-4.67-3.5-7-3.5zm8 0c-.29 0-.62.02-.97.05 1.16.84 1.97 1.97 1.97 3.45V19h6v-2.5c0-2.33-4.67-3.5-7-3.5z"/>
            </svg>
          </div>
          <div>
            <h1 style={{ 
              fontSize: '32px', 
              fontWeight: '800', 
              color: '#0f172a',
              margin: '0 0 4px 0',
              letterSpacing: '-0.5px'
            }}>
              User Management
            </h1>
            <p style={{ color: '#64748b', margin: 0, fontSize: '15px', fontWeight: '500' }}>
              View and manage all users across the platform
            </p>
          </div>
        </div>
      </div>

      <div style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))',
        gap: '20px',
        marginBottom: '32px'
      }}>
        {[
          { key: 'all', label: 'Total Users', count: stats.all, gradient: 'linear-gradient(135deg, #3b82f6 0%, #2563eb 100%)', icon: '' },
          { key: 'player', label: 'Players', count: stats.player, gradient: 'linear-gradient(135deg, #9333ea 0%, #7e22ce 100%)', icon: '' },
          { key: 'coach', label: 'Coaches', count: stats.coach, gradient: 'linear-gradient(135deg, #ff8a50 0%, #ff6b35 100%)', icon: '' },
          { key: 'venue_owner', label: 'Venue Owners', count: stats.venue_owner, gradient: 'linear-gradient(135deg, #0891b2ff 0%, #0e7490 100%)', icon: '' }
        ].map(({ key, label, count, gradient, icon }) => (
          <button
            key={key}
            onClick={() => setRoleFilter(key)}
            style={{
              position: 'relative',
              padding: '24px',
              background: 'white',
              borderRadius: '20px',
              border: roleFilter === key ? '3px solid #8b5cf6' : '3px solid transparent',
              cursor: 'pointer',
              transition: 'all 0.3s cubic-bezier(0.4, 0, 0.2, 1)',
              boxShadow: roleFilter === key 
                ? '0 20px 40px rgba(139, 92, 246, 0.15)' 
                : '0 4px 12px rgba(0, 0, 0, 0.08)',
              transform: roleFilter === key ? 'translateY(-4px)' : 'translateY(0)',
              overflow: 'hidden'
            }}
            onMouseEnter={(e) => {
              if (roleFilter !== key) {
                e.currentTarget.style.transform = 'translateY(-2px)';
                e.currentTarget.style.boxShadow = '0 12px 24px rgba(0, 0, 0, 0.12)';
              }
            }}
            onMouseLeave={(e) => {
              if (roleFilter !== key) {
                e.currentTarget.style.transform = 'translateY(0)';
                e.currentTarget.style.boxShadow = '0 4px 12px rgba(0, 0, 0, 0.08)';
              }
            }}
          >
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
              <div style={{ textAlign: 'left' }}>
                <p style={{ 
                  margin: '0 0 8px 0', 
                  fontSize: '12px', 
                  fontWeight: '700', 
                  color: '#64748b', 
                  textTransform: 'uppercase', 
                  letterSpacing: '1px' 
                }}>
                  {label}
                </p>
                <p style={{ 
                  margin: 0, 
                  fontSize: '36px', 
                  fontWeight: '800', 
                  color: '#0f172a',
                  lineHeight: '1'
                }}>
                  {count}
                </p>
              </div>
              <div style={{
                width: '56px',
                height: '56px',
                background: gradient,
                borderRadius: '16px',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontSize: '24px',
                boxShadow: '0 8px 20px rgba(0, 0, 0, 0.15)'
              }}>
                {icon}
              </div>
            </div>
            {roleFilter === key && (
              <div style={{
                position: 'absolute',
                bottom: 0,
                left: 0,
                right: 0,
                height: '4px',
                background: 'linear-gradient(90deg, #8b5cf6, #7c3aed)',
                borderRadius: '0 0 17px 17px'
              }} />
            )}
          </button>
        ))}
      </div>

      <div style={{
        background: 'white',
        padding: '24px',
        borderRadius: '20px',
        marginBottom: '24px',
        border: '2px solid #f1f5f9',
        boxShadow: '0 4px 12px rgba(0, 0, 0, 0.08)'
      }}>
        <div style={{ display: 'flex', gap: '16px', flexWrap: 'wrap', alignItems: 'center' }}>
          <div style={{ flex: 1, minWidth: '250px', position: 'relative' }}>
            <div style={{
              position: 'absolute',
              left: '16px',
              top: '50%',
              transform: 'translateY(-50%)',
              color: '#9ca3af',
              pointerEvents: 'none'
            }}>
              <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
                <path d="M15.5 14h-.79l-.28-.27C15.41 12.59 16 11.11 16 9.5 16 5.91 13.09 3 9.5 3S3 5.91 3 9.5 5.91 16 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z"/>
              </svg>
            </div>
            <input
              type="text"
              placeholder="Search by name, email, or role..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              style={{
                width: '100%',
                padding: '12px 16px 12px 48px',
                border: '2px solid #e5e7eb',
                borderRadius: '12px',
                fontSize: '14px',
                outline: 'none',
                transition: 'all 0.2s ease',
                fontWeight: '500',
                boxSizing: 'border-box'
              }}
              onFocus={(e) => {
                e.target.style.borderColor = '#8b5cf6';
                e.target.style.boxShadow = '0 0 0 3px rgba(139, 92, 246, 0.1)';
              }}
              onBlur={(e) => {
                e.target.style.borderColor = '#e5e7eb';
                e.target.style.boxShadow = 'none';
              }}
            />
          </div>

          <button
            onClick={fetchAllUsers}
            disabled={isLoading}
            style={{
              padding: '12px 24px',
              background: 'linear-gradient(135deg, #8b5cf6 0%, #7c3aed 100%)',
              color: 'white',
              border: 'none',
              borderRadius: '12px',
              fontSize: '14px',
              fontWeight: '700',
              cursor: isLoading ? 'not-allowed' : 'pointer',
              opacity: isLoading ? 0.6 : 1,
              transition: 'all 0.3s ease',
              boxShadow: '0 4px 12px rgba(139, 92, 246, 0.3)',
              display: 'flex',
              alignItems: 'center',
              gap: '8px',
              textTransform: 'uppercase',
              letterSpacing: '0.5px'
            }}
            onMouseEnter={(e) => {
              if (!isLoading) {
                e.target.style.transform = 'translateY(-2px)';
                e.target.style.boxShadow = '0 8px 20px rgba(139, 92, 246, 0.4)';
              }
            }}
            onMouseLeave={(e) => {
              if (!isLoading) {
                e.target.style.transform = 'translateY(0)';
                e.target.style.boxShadow = '0 4px 12px rgba(139, 92, 246, 0.3)';
              }
            }}
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
              <path d="M17.65 6.35C16.2 4.9 14.21 4 12 4c-4.42 0-7.99 3.58-7.99 8s3.57 8 7.99 8c3.73 0 6.84-2.55 7.73-6h-2.08c-.82 2.33-3.04 4-5.65 4-3.31 0-6-2.69-6-6s2.69-6 6-6c1.66 0 3.14.69 4.22 1.78L13 11h7V4l-2.35 2.35z"/>
            </svg>
            {isLoading ? 'Loading...' : 'Refresh'}
          </button>
        </div>
      </div>

      <div style={{
        background: 'white',
        borderRadius: '20px',
        border: '2px solid #f1f5f9',
        overflow: 'hidden',
        boxShadow: '0 4px 20px rgba(0, 0, 0, 0.08)'
      }}>
        {filteredUsers.length === 0 ? (
          <div style={{ 
            padding: '80px 32px', 
            textAlign: 'center'
          }}>
            <div style={{ 
              fontSize: '64px',
              marginBottom: '20px'
            }}>🔍</div>
            <h3 style={{ 
              color: '#475569', 
              margin: '0 0 12px 0',
              fontSize: '20px',
              fontWeight: '700'
            }}>
              No users found
            </h3>
            <p style={{ 
              color: '#94a3b8', 
              margin: 0,
              fontSize: '15px'
            }}>
              Try adjusting your search or filter criteria
            </p>
          </div>
        ) : (
          <>
            <div style={{ overflowX: 'auto' }}>
              <table style={{ 
                width: '100%', 
                borderCollapse: 'collapse'
              }}>
                <thead>
                  <tr style={{ background: 'linear-gradient(135deg, #f8fafc 0%, #f1f5f9 100%)' }}>
                    <th style={{ 
                      padding: '18px 24px', 
                      textAlign: 'left',
                      fontWeight: '700',
                      fontSize: '12px',
                      color: '#64748b',
                      textTransform: 'uppercase',
                      letterSpacing: '1px',
                      borderBottom: '2px solid #e2e8f0'
                    }}>
                      Name
                    </th>
                    <th style={{ 
                      padding: '18px 24px', 
                      textAlign: 'left',
                      fontWeight: '700',
                      fontSize: '12px',
                      color: '#64748b',
                      textTransform: 'uppercase',
                      letterSpacing: '1px',
                      borderBottom: '2px solid #e2e8f0'
                    }}>
                      Email
                    </th>
                    <th style={{ 
                      padding: '18px 24px', 
                      textAlign: 'left',
                      fontWeight: '700',
                      fontSize: '12px',
                      color: '#64748b',
                      textTransform: 'uppercase',
                      letterSpacing: '1px',
                      borderBottom: '2px solid #e2e8f0'
                    }}>
                      Role
                    </th>
                    <th style={{ 
                      padding: '18px 24px', 
                      textAlign: 'left',
                      fontWeight: '700',
                      fontSize: '12px',
                      color: '#64748b',
                      textTransform: 'uppercase',
                      letterSpacing: '1px',
                      borderBottom: '2px solid #e2e8f0'
                    }}>
                      Phone
                    </th>
                    <th style={{ 
                      padding: '18px 24px', 
                      textAlign: 'left',
                      fontWeight: '700',
                      fontSize: '12px',
                      color: '#64748b',
                      textTransform: 'uppercase',
                      letterSpacing: '1px',
                      borderBottom: '2px solid #e2e8f0'
                    }}>
                      Status
                    </th>
                    <th style={{ 
                      padding: '18px 24px', 
                      textAlign: 'left',
                      fontWeight: '700',
                      fontSize: '12px',
                      color: '#64748b',
                      textTransform: 'uppercase',
                      letterSpacing: '1px',
                      borderBottom: '2px solid #e2e8f0'
                    }}>
                      Joined
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {filteredUsers.map((user, index) => {
                    const roleBadge = getRoleBadgeColor(user.role);
                    return (
                      <tr 
                        key={user.id}
                        style={{ 
                          borderBottom: '1px solid #f1f5f9',
                          background: index % 2 === 0 ? 'white' : '#fafbfc',
                          transition: 'all 0.2s ease'
                        }}
                        onMouseEnter={(e) => {
                          e.currentTarget.style.background = '#f8f9fa';
                          e.currentTarget.style.transform = 'scale(1.01)';
                        }}
                        onMouseLeave={(e) => {
                          e.currentTarget.style.background = index % 2 === 0 ? 'white' : '#fafbfc';
                          e.currentTarget.style.transform = 'scale(1)';
                        }}
                      >
                        <td style={{ 
                          padding: '18px 24px',
                          fontSize: '14px',
                          fontWeight: '600',
                          color: '#0f172a'
                        }}>
                          <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                            <div style={{
                              width: '40px',
                              height: '40px',
                              borderRadius: '12px',
                              background: 'linear-gradient(135deg, #8b5cf6 0%, #7c3aed 100%)',
                              display: 'flex',
                              alignItems: 'center',
                              justifyContent: 'center',
                              color: 'white',
                              fontWeight: '700',
                              fontSize: '16px',
                              flexShrink: 0
                            }}>
                              {user.name.charAt(0).toUpperCase()}
                            </div>
                            <span>{user.name}</span>
                          </div>
                        </td>
                        <td style={{ 
                          padding: '18px 24px',
                          fontSize: '14px',
                          color: '#64748b',
                          fontWeight: '500'
                        }}>
                          {user.email}
                        </td>
                        <td style={{ padding: '18px 24px' }}>
                          <span style={{
                            display: 'inline-flex',
                            alignItems: 'center',
                            gap: '6px',
                            padding: '6px 14px',
                            backgroundColor: roleBadge.bg,
                            color: roleBadge.text,
                            borderRadius: '10px',
                            fontSize: '12px',
                            fontWeight: '700',
                            textTransform: 'uppercase',
                            letterSpacing: '0.3px'
                          }}>
                            {user.role === 'player' && ''}
                            {user.role === 'coach' && ''}
                            {user.role === 'venue_owner' && ''}
                            {getRoleDisplayName(user.role)}
                          </span>
                        </td>
                        <td style={{ 
                          padding: '18px 24px',
                          fontSize: '14px',
                          color: '#64748b',
                          fontWeight: '500'
                        }}>
                          {user.phone}
                        </td>
                        <td style={{ padding: '18px 24px' }}>
                          <span style={{
                            display: 'inline-flex',
                            alignItems: 'center',
                            gap: '6px',
                            padding: '6px 12px',
                            backgroundColor: user.isActive ? '#d1fae5' : '#fee2e2',
                            color: user.isActive ? '#065f46' : '#991b1b',
                            borderRadius: '10px',
                            fontSize: '12px',
                            fontWeight: '700'
                          }}>
                            <div style={{
                              width: '8px',
                              height: '8px',
                              borderRadius: '50%',
                              background: user.isActive ? '#10b981' : '#ef4444'
                            }} />
                            {user.isActive ? 'Active' : 'Inactive'}
                          </span>
                        </td>
                        <td style={{ 
                          padding: '18px 24px',
                          fontSize: '14px',
                          color: '#64748b',
                          fontWeight: '500'
                        }}>
                          {formatDate(user.createdAt)}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>

            <div style={{
              padding: '20px 24px',
              background: 'linear-gradient(135deg, #f8fafc 0%, #f1f5f9 100%)',
              borderTop: '2px solid #e2e8f0',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              flexWrap: 'wrap',
              gap: '12px'
            }}>
              <div style={{
                display: 'flex',
                alignItems: 'center',
                gap: '8px',
                color: '#64748b',
                fontSize: '14px',
                fontWeight: '600'
              }}>
                <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor">
                  <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/>
                </svg>
                Showing {filteredUsers.length} of {allUsers.length} users
              </div>
              
              <div style={{
                padding: '8px 16px',
                background: 'white',
                borderRadius: '10px',
                fontSize: '13px',
                fontWeight: '600',
                color: '#8b5cf6',
                border: '2px solid #e9d5ff',
                display: 'flex',
                alignItems: 'center',
                gap: '6px'
              }}>
                <div style={{
                  width: '8px',
                  height: '8px',
                  borderRadius: '50%',
                  background: '#10b981',
                  animation: 'pulse 2s infinite'
                }} />
                Live Data
              </div>
            </div>
          </>
        )}
      </div>

      <style>{`
        @keyframes pulse {
          0%, 100% { opacity: 1; }
          50% { opacity: 0.5; }
        }
      `}</style>
    </div>
  );
};

export default UserManagementPage;