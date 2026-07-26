'use client';
import React, { useState, useRef, useEffect } from 'react';
import { ChevronDown, Check, Search, X } from 'lucide-react';

export interface SelectOption {
  value: string;
  label: string;
  badge?: string;
  color?: string;
}

interface TacticalSelectProps {
  value: string;
  options: SelectOption[];
  onChange: (value: string) => void;
  placeholder?: string;
  icon?: React.ReactNode;
  accentColor?: string;
  searchable?: boolean;
  maxWidth?: number | string;
  className?: string;
}

export default function TacticalSelect({
  value,
  options,
  onChange,
  placeholder = 'Select option',
  icon,
  accentColor = 'var(--primary)',
  searchable,
  maxWidth = 260,
}: TacticalSelectProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const containerRef = useRef<HTMLDivElement>(null);
  const searchInputRef = useRef<HTMLInputElement>(null);

  const selectedOption = options.find((opt) => opt.value === value);

  // Auto-enable search if more than 8 options
  const isSearchable = searchable ?? options.length > 8;

  const filteredOptions = isSearchable && searchQuery
    ? options.filter(
        (opt) =>
          opt.label.toLowerCase().includes(searchQuery.toLowerCase()) ||
          opt.value.toLowerCase().includes(searchQuery.toLowerCase())
      )
    : options;

  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setIsOpen(false);
      }
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  useEffect(() => {
    if (isOpen && isSearchable && searchInputRef.current) {
      setTimeout(() => searchInputRef.current?.focus(), 50);
    }
    if (!isOpen) {
      setSearchQuery('');
    }
  }, [isOpen, isSearchable]);

  return (
    <div
      ref={containerRef}
      style={{
        position: 'relative',
        display: 'inline-block',
        maxWidth: typeof maxWidth === 'number' ? `${maxWidth}px` : maxWidth,
        width: '100%',
        fontFamily: "'Outfit', 'Inter', sans-serif",
      }}
    >
      {/* Trigger Button */}
      <button
        type="button"
        onClick={() => setIsOpen(!isOpen)}
        style={{
          width: '100%',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          gap: 8,
          padding: '7px 12px',
          background: isOpen ? 'var(--bg-tertiary, #1e293b)' : 'var(--bg-secondary, #0f172a)',
          border: `1px solid ${isOpen ? accentColor : 'var(--border, rgba(255,255,255,0.12))'}`,
          borderRadius: 10,
          color: 'var(--text-primary, #f8fafc)',
          fontSize: 11,
          fontWeight: 800,
          cursor: 'pointer',
          outline: 'none',
          transition: 'all 0.2s cubic-bezier(0.4, 0, 0.2, 1)',
          boxShadow: isOpen ? `0 0 12px ${accentColor}33` : '0 2px 4px rgba(0,0,0,0.1)',
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, minWidth: 0, overflow: 'hidden' }}>
          {icon && <span style={{ display: 'flex', alignItems: 'center', flexShrink: 0, color: accentColor }}>{icon}</span>}
          <span
            style={{
              overflow: 'hidden',
              textOverflow: 'ellipsis',
              whiteSpace: 'nowrap',
              color: selectedOption?.value !== 'ALL' ? accentColor : 'var(--text-primary)',
              letterSpacing: 0.5,
              textTransform: 'uppercase',
            }}
          >
            {selectedOption ? selectedOption.label : placeholder}
          </span>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: 6, flexShrink: 0 }}>
          {selectedOption?.badge && (
            <span
              style={{
                fontSize: 9,
                fontWeight: 900,
                padding: '2px 6px',
                borderRadius: 6,
                background: `${accentColor}22`,
                color: accentColor,
                border: `1px solid ${accentColor}44`,
              }}
            >
              {selectedOption.badge}
            </span>
          )}
          <ChevronDown
            size={14}
            style={{
              transform: isOpen ? 'rotate(180deg)' : 'rotate(0deg)',
              transition: 'transform 0.2s ease',
              color: 'var(--text-muted, #94a3b8)',
            }}
          />
        </div>
      </button>

      {/* Popover Menu */}
      {isOpen && (
        <div
          style={{
            position: 'absolute',
            top: 'calc(100% + 6px)',
            left: 0,
            right: 0,
            zIndex: 9999,
            minWidth: 220,
            maxHeight: 280,
            background: 'rgba(15, 23, 42, 0.98)',
            backdropFilter: 'blur(16px)',
            WebkitBackdropFilter: 'blur(16px)',
            border: '1px solid rgba(255, 255, 255, 0.15)',
            borderRadius: 12,
            boxShadow: '0 20px 40px rgba(0,0,0,0.6), 0 0 0 1px rgba(255,255,255,0.05)',
            overflow: 'hidden',
            display: 'flex',
            flexDirection: 'column',
            animation: 'fadeIn 0.15s ease-out',
          }}
        >
          {/* Search Bar if Searchable */}
          {isSearchable && (
            <div
              style={{
                padding: '8px 10px',
                borderBottom: '1px solid rgba(255, 255, 255, 0.08)',
                display: 'flex',
                alignItems: 'center',
                gap: 6,
                background: 'rgba(0, 0, 0, 0.2)',
              }}
            >
              <Search size={12} style={{ color: 'var(--text-muted, #94a3b8)', flexShrink: 0 }} />
              <input
                ref={searchInputRef}
                type="text"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder="Search..."
                style={{
                  width: '100%',
                  background: 'transparent',
                  border: 'none',
                  outline: 'none',
                  color: 'white',
                  fontSize: 11,
                  fontFamily: 'inherit',
                  fontWeight: 600,
                }}
              />
              {searchQuery && (
                <button
                  type="button"
                  onClick={() => setSearchQuery('')}
                  style={{ background: 'none', border: 'none', color: '#94a3b8', cursor: 'pointer', padding: 2 }}
                >
                  <X size={12} />
                </button>
              )}
            </div>
          )}

          {/* Options List */}
          <div style={{ flex: 1, overflowY: 'auto', padding: '4px' }}>
            {filteredOptions.length === 0 ? (
              <div style={{ padding: '12px 10px', fontSize: 11, color: '#94a3b8', textAlign: 'center' }}>
                No matching options
              </div>
            ) : (
              filteredOptions.map((opt) => {
                const isSelected = opt.value === value;
                return (
                  <button
                    key={opt.value}
                    type="button"
                    onClick={() => {
                      onChange(opt.value);
                      setIsOpen(false);
                    }}
                    style={{
                      width: '100%',
                      textAlign: 'left',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'space-between',
                      gap: 8,
                      padding: '8px 10px',
                      borderRadius: 8,
                      background: isSelected ? `${accentColor}22` : 'transparent',
                      border: 'none',
                      color: isSelected ? accentColor : 'var(--text-primary, #f8fafc)',
                      fontSize: 11,
                      fontWeight: isSelected ? 800 : 600,
                      cursor: 'pointer',
                      transition: 'background 0.15s ease',
                      outline: 'none',
                    }}
                    onMouseEnter={(e) => {
                      if (!isSelected) e.currentTarget.style.background = 'rgba(255, 255, 255, 0.06)';
                    }}
                    onMouseLeave={(e) => {
                      if (!isSelected) e.currentTarget.style.background = 'transparent';
                    }}
                  >
                    <span
                      style={{
                        overflow: 'hidden',
                        textOverflow: 'ellipsis',
                        whiteSpace: 'nowrap',
                        letterSpacing: 0.3,
                      }}
                    >
                      {opt.label}
                    </span>

                    <div style={{ display: 'flex', alignItems: 'center', gap: 6, flexShrink: 0 }}>
                      {opt.badge && (
                        <span
                          style={{
                            fontSize: 9,
                            fontWeight: 800,
                            padding: '1px 5px',
                            borderRadius: 4,
                            background: 'rgba(255, 255, 255, 0.08)',
                            color: '#94a3b8',
                          }}
                        >
                          {opt.badge}
                        </span>
                      )}
                      {isSelected && <Check size={14} style={{ color: accentColor }} />}
                    </div>
                  </button>
                );
              })
            )}
          </div>
        </div>
      )}
    </div>
  );
}
